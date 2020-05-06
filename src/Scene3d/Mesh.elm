module Scene3d.Mesh exposing
    ( Mesh
    , Plain, Uniform, Unlit, Textured
    , points, lineSegments, polyline
    , triangles, facets
    , indexedTriangles, indexedFacets, indexedFaces
    , texturedTriangles, texturedFacets, texturedFaces
    , Shadow, shadow
    , cullBackFaces
    )

{-|

@docs Mesh


## Specific mesh types

@docs Plain, Uniform, Unlit, Textured


# Constructors

@docs points, lineSegments, polyline

@docs triangles, facets

@docs indexedTriangles, indexedFacets, indexedFaces

@docs texturedTriangles, texturedFacets, texturedFaces


# Shadows

@docs Shadow, shadow


# Optimizations

@docs cullBackFaces

-}

import Array
import BoundingBox3d exposing (BoundingBox3d)
import Dict exposing (Dict)
import Geometry.Interop.LinearAlgebra.Point3d as Point3d
import Geometry.Interop.LinearAlgebra.Vector3d as Vector3d
import Length exposing (Meters)
import LineSegment3d exposing (LineSegment3d)
import Math.Vector2 exposing (Vec2)
import Math.Vector3 exposing (Vec3)
import Pixels exposing (Pixels, inPixels)
import Point3d exposing (Point3d)
import Polyline3d exposing (Polyline3d)
import Quantity exposing (Quantity(..), Unitless)
import Scene3d.Types as Types
    exposing
        ( BackFaceSetting(..)
        , Bounds
        , PlainVertex
        , Shadow
        , VertexWithNormal
        , VertexWithNormalAndUv
        , VertexWithTangent
        , VertexWithUv
        )
import Triangle3d exposing (Triangle3d)
import TriangularMesh exposing (TriangularMesh)
import Vector3d exposing (Vector3d)
import WebGL


{-| TODO
-}
type alias Mesh coordinates attributes =
    Types.Mesh coordinates attributes


{-| A mesh containing vertex positions only.
-}
type alias Plain coordinates =
    Mesh coordinates {}


{-| A mesh with normal vectors at each vertex but no UV (texture) coordinates,
meaning that surface appearance will be uniform across the mesh.
-}
type alias Uniform coordinates =
    Mesh coordinates { normals : () }


{-| A mesh with UV coordinates at each vertex but no normal vectors (normal
vectors are required for any kind of lighting calculation).
-}
type alias Unlit coordinates =
    Mesh coordinates { uvs : () }


{-| A mesh with both normal vectors and UV coordinates at each vertex, allowing
for general-purpose texturing of lit objects.
-}
type alias Textured coordinates =
    Mesh coordinates { normals : (), uvs : () }


{-| A mesh with normal vectors, UV coordinates and tangent vectors at each
vertex, allowing for full texturing including normal maps.
-}
type alias NormalMapped coordinates =
    Mesh coordinates { normals : (), uvs : (), tangents : () }


{-| A mesh with normal and tangent vectors but no UV coordinates, allowing for
some specialized material models such as brushed metal but no texturing.
-}
type alias Anisotropic coordinates =
    Mesh coordinates { normals : (), tangents : () }


{-| TODO
-}
type alias Shadow coordinates =
    Types.Shadow coordinates


{-| TODO
-}
empty : Mesh coordinates attributes
empty =
    Types.EmptyMesh


plainVertex : Point3d Meters coordinates -> PlainVertex
plainVertex point =
    { position = Point3d.toVec3 point }


triangleAttributes :
    Triangle3d Meters coordinates
    -> ( PlainVertex, PlainVertex, PlainVertex )
triangleAttributes triangle =
    let
        ( p1, p2, p3 ) =
            Triangle3d.vertices triangle
    in
    ( plainVertex p1, plainVertex p2, plainVertex p3 )


triangleNormal :
    Point3d Meters coordinates
    -> Point3d Meters coordinates
    -> Point3d Meters coordinates
    -> Vector3d Unitless coordinates
triangleNormal p1 p2 p3 =
    let
        v1 =
            Vector3d.from p1 p2

        v2 =
            Vector3d.from p2 p3
    in
    Vector3d.normalize (v1 |> Vector3d.cross v2)


facetAttributes :
    Triangle3d Meters coordinates
    -> ( VertexWithNormal, VertexWithNormal, VertexWithNormal )
facetAttributes triangle =
    let
        ( p1, p2, p3 ) =
            Triangle3d.vertices triangle

        normal =
            Vector3d.toVec3 (triangleNormal p1 p2 p3)
    in
    ( { position = Point3d.toVec3 p1, normal = normal }
    , { position = Point3d.toVec3 p2, normal = normal }
    , { position = Point3d.toVec3 p3, normal = normal }
    )


{-| TODO
-}
triangles : List (Triangle3d Meters coordinates) -> Plain coordinates
triangles givenTriangles =
    case givenTriangles of
        [] ->
            Types.EmptyMesh

        first :: rest ->
            let
                bounds =
                    BoundingBox3d.aggregateOf Triangle3d.boundingBox first rest

                webGLMesh =
                    WebGL.triangles (List.map triangleAttributes givenTriangles)
            in
            Types.Triangles bounds givenTriangles webGLMesh KeepBackFaces


{-| TODO
-}
facets : List (Triangle3d Meters coordinates) -> Uniform coordinates
facets givenTriangles =
    case givenTriangles of
        [] ->
            Types.EmptyMesh

        first :: rest ->
            let
                bounds =
                    BoundingBox3d.aggregateOf Triangle3d.boundingBox first rest

                webGLMesh =
                    WebGL.triangles (List.map facetAttributes givenTriangles)
            in
            Types.Facets bounds givenTriangles webGLMesh KeepBackFaces


collectPlain : Point3d Meters coordinates -> List PlainVertex -> List PlainVertex
collectPlain point accumulated =
    { position = Point3d.toVec3 point } :: accumulated


plainBoundsHelp :
    Float
    -> Float
    -> Float
    -> Float
    -> Float
    -> Float
    -> List PlainVertex
    -> BoundingBox3d Meters coordinates
plainBoundsHelp minX maxX minY maxY minZ maxZ remaining =
    case remaining of
        next :: rest ->
            let
                x =
                    Math.Vector3.getX next.position

                y =
                    Math.Vector3.getY next.position

                z =
                    Math.Vector3.getZ next.position
            in
            plainBoundsHelp
                (min minX x)
                (max maxX x)
                (min minY y)
                (max maxY y)
                (min minZ z)
                (max maxZ z)
                rest

        [] ->
            BoundingBox3d.fromExtrema
                { minX = Quantity minX
                , maxX = Quantity maxX
                , minY = Quantity minY
                , maxY = Quantity maxY
                , minZ = Quantity minZ
                , maxZ = Quantity maxZ
                }


plainBounds : PlainVertex -> List PlainVertex -> BoundingBox3d Meters coordinates
plainBounds first rest =
    let
        x =
            Math.Vector3.getX first.position

        y =
            Math.Vector3.getY first.position

        z =
            Math.Vector3.getZ first.position
    in
    plainBoundsHelp x x y y z z rest


{-| TODO
-}
indexedTriangles : TriangularMesh (Point3d Meters coordinates) -> Plain coordinates
indexedTriangles givenMesh =
    let
        collectedVertices =
            Array.foldr collectPlain [] (TriangularMesh.vertices givenMesh)
    in
    case collectedVertices of
        [] ->
            Types.EmptyMesh

        first :: rest ->
            let
                bounds =
                    plainBounds first rest

                webGLMesh =
                    WebGL.indexedTriangles
                        collectedVertices
                        (TriangularMesh.faceIndices givenMesh)
            in
            Types.Indexed bounds givenMesh webGLMesh KeepBackFaces


{-| TODO
-}
indexedFacets : TriangularMesh (Point3d Meters coordinates) -> Uniform coordinates
indexedFacets givenMesh =
    facets (List.map Triangle3d.fromVertices (TriangularMesh.faceVertices givenMesh))


collectSmooth :
    { position : Point3d Meters coordinates, normal : Vector3d Unitless coordinates }
    -> List VertexWithNormal
    -> List VertexWithNormal
collectSmooth { position, normal } accumulated =
    { position = Point3d.toVec3 position, normal = Vector3d.toVec3 normal }
        :: accumulated


vertexBoundsHelp :
    Float
    -> Float
    -> Float
    -> Float
    -> Float
    -> Float
    -> List { a | position : Vec3 }
    -> BoundingBox3d Meters coordinates
vertexBoundsHelp minX maxX minY maxY minZ maxZ remaining =
    case remaining of
        next :: rest ->
            let
                x =
                    Math.Vector3.getX next.position

                y =
                    Math.Vector3.getY next.position

                z =
                    Math.Vector3.getZ next.position
            in
            vertexBoundsHelp
                (min minX x)
                (max maxX x)
                (min minY y)
                (max maxY y)
                (min minZ z)
                (max maxZ z)
                rest

        [] ->
            BoundingBox3d.fromExtrema
                { minX = Quantity minX
                , maxX = Quantity maxX
                , minY = Quantity minY
                , maxY = Quantity maxY
                , minZ = Quantity minZ
                , maxZ = Quantity maxZ
                }


vertexBounds : { a | position : Vec3 } -> List { a | position : Vec3 } -> BoundingBox3d Meters coordinates
vertexBounds first rest =
    let
        x =
            Math.Vector3.getX first.position

        y =
            Math.Vector3.getY first.position

        z =
            Math.Vector3.getZ first.position
    in
    vertexBoundsHelp x x y y z z rest


{-| TODO
-}
indexedFaces :
    TriangularMesh { position : Point3d Meters coordinates, normal : Vector3d Unitless coordinates }
    -> Uniform coordinates
indexedFaces givenMesh =
    let
        collectedVertices =
            Array.foldr collectSmooth [] (TriangularMesh.vertices givenMesh)
    in
    case collectedVertices of
        [] ->
            Types.EmptyMesh

        first :: rest ->
            let
                bounds =
                    vertexBounds first rest

                webGLMesh =
                    WebGL.indexedTriangles
                        collectedVertices
                        (TriangularMesh.faceIndices givenMesh)
            in
            Types.MeshWithNormals bounds givenMesh webGLMesh KeepBackFaces


collectTextured :
    { position : Point3d Meters coordinates, uv : ( Float, Float ) }
    -> List VertexWithUv
    -> List VertexWithUv
collectTextured { position, uv } accumulated =
    let
        ( u, v ) =
            uv
    in
    { position = Point3d.toVec3 position, uv = Math.Vector2.vec2 u v }
        :: accumulated


{-| TODO
-}
texturedTriangles :
    TriangularMesh { position : Point3d Meters coordinates, uv : ( Float, Float ) }
    -> Unlit coordinates
texturedTriangles givenMesh =
    let
        collectedVertices =
            Array.foldr collectTextured [] (TriangularMesh.vertices givenMesh)
    in
    case collectedVertices of
        [] ->
            Types.EmptyMesh

        first :: rest ->
            let
                bounds =
                    vertexBounds first rest

                webGLMesh =
                    WebGL.indexedTriangles
                        collectedVertices
                        (TriangularMesh.faceIndices givenMesh)
            in
            Types.MeshWithUvs bounds givenMesh webGLMesh KeepBackFaces


type alias TexturedTriangleVertex coordinates =
    { position : Point3d Meters coordinates
    , uv : ( Float, Float )
    }


type alias TexturedFacetVertex coordinates =
    { position : Point3d Meters coordinates
    , uv : ( Float, Float )
    , normal : Vector3d Unitless coordinates
    }


collectTexturedFacetVertices :
    ( TexturedTriangleVertex coordinates, TexturedTriangleVertex coordinates, TexturedTriangleVertex coordinates )
    -> List (TexturedFacetVertex coordinates)
    -> List (TexturedFacetVertex coordinates)
collectTexturedFacetVertices ( tv1, tv2, tv3 ) accumulated =
    let
        normal =
            triangleNormal tv1.position tv2.position tv3.position

        fv1 =
            { position = tv1.position
            , uv = tv1.uv
            , normal = normal
            }

        fv2 =
            { position = tv2.position
            , uv = tv2.uv
            , normal = normal
            }

        fv3 =
            { position = tv3.position
            , uv = tv3.uv
            , normal = normal
            }
    in
    fv1 :: fv2 :: fv3 :: accumulated


texturedFacetFaceIndices : Int -> List ( Int, Int, Int ) -> List ( Int, Int, Int )
texturedFacetFaceIndices count accumulated =
    if count <= 0 then
        accumulated

    else
        texturedFacetFaceIndices (count - 3) (( count - 3, count - 2, count - 1 ) :: accumulated)


{-| TODO
-}
texturedFacets :
    TriangularMesh { position : Point3d Meters coordinates, uv : ( Float, Float ) }
    -> Textured coordinates
texturedFacets givenMesh =
    let
        collectedVertices =
            Array.fromList <|
                List.foldr collectTexturedFacetVertices [] <|
                    TriangularMesh.faceVertices givenMesh

        faceIndices =
            texturedFacetFaceIndices (Array.length collectedVertices) []
    in
    texturedFaces (TriangularMesh.indexed collectedVertices faceIndices)


collectSmoothTextured :
    { position : Point3d Meters coordinates, normal : Vector3d Unitless coordinates, uv : ( Float, Float ) }
    -> List VertexWithNormalAndUv
    -> List VertexWithNormalAndUv
collectSmoothTextured { position, normal, uv } accumulated =
    let
        ( u, v ) =
            uv
    in
    { position = Point3d.toVec3 position, normal = Vector3d.toVec3 normal, uv = Math.Vector2.vec2 u v }
        :: accumulated


{-| TODO
-}
texturedFaces :
    TriangularMesh
        { position : Point3d Meters coordinates
        , normal : Vector3d Unitless coordinates
        , uv : ( Float, Float )
        }
    -> Textured coordinates
texturedFaces givenMesh =
    let
        collectedVertices =
            Array.foldr collectSmoothTextured [] (TriangularMesh.vertices givenMesh)
    in
    case collectedVertices of
        [] ->
            Types.EmptyMesh

        first :: rest ->
            let
                bounds =
                    vertexBounds first rest

                webGLMesh =
                    WebGL.indexedTriangles
                        collectedVertices
                        (TriangularMesh.faceIndices givenMesh)
            in
            Types.MeshWithNormalsAndUvs bounds givenMesh webGLMesh KeepBackFaces


collectNormalMapped :
    { position : Point3d Meters coordinates, normal : Vector3d Unitless coordinates, uv : ( Float, Float ), tangent : Vector3d Unitless coordinates }
    -> List VertexWithTangent
    -> List VertexWithTangent
collectNormalMapped { position, normal, uv, tangent } accumulated =
    let
        ( u, v ) =
            uv
    in
    { position = Point3d.toVec3 position, normal = Vector3d.toVec3 normal, uv = Math.Vector2.vec2 u v, tangent = Vector3d.toVec3 tangent }
        :: accumulated


normalMapped :
    TriangularMesh
        { position : Point3d Meters coordinates
        , normal : Vector3d Unitless coordinates
        , uv : ( Float, Float )
        , tangent : Vector3d Unitless coordinates
        }
    -> NormalMapped coordinates
normalMapped givenMesh =
    let
        collectedVertices =
            Array.foldr collectNormalMapped [] (TriangularMesh.vertices givenMesh)
    in
    case collectedVertices of
        [] ->
            Types.EmptyMesh

        first :: rest ->
            let
                bounds =
                    vertexBounds first rest

                webGLMesh =
                    WebGL.indexedTriangles
                        collectedVertices
                        (TriangularMesh.faceIndices givenMesh)
            in
            Types.MeshWithTangents bounds givenMesh webGLMesh KeepBackFaces


lineSegmentAttributes : LineSegment3d Meters coordinates -> ( PlainVertex, PlainVertex )
lineSegmentAttributes givenSegment =
    let
        ( p1, p2 ) =
            LineSegment3d.endpoints givenSegment
    in
    ( plainVertex p1, plainVertex p2 )


{-| TODO
-}
lineSegments : List (LineSegment3d Meters coordinates) -> Plain coordinates
lineSegments givenSegments =
    case givenSegments of
        [] ->
            Types.EmptyMesh

        first :: rest ->
            let
                bounds =
                    BoundingBox3d.aggregateOf LineSegment3d.boundingBox first rest

                webGLMesh =
                    WebGL.lines (List.map lineSegmentAttributes givenSegments)
            in
            Types.LineSegments bounds givenSegments webGLMesh


{-| TODO
-}
polyline : Polyline3d Meters coordinates -> Plain coordinates
polyline givenPolyline =
    let
        vertices =
            Polyline3d.vertices givenPolyline
    in
    case vertices of
        [] ->
            Types.EmptyMesh

        first :: rest ->
            let
                bounds =
                    BoundingBox3d.hull first rest

                webGLMesh =
                    WebGL.lineStrip (List.map plainVertex vertices)
            in
            Types.Polyline bounds givenPolyline webGLMesh


{-| TODO
-}
points :
    { radius : Quantity Float Pixels }
    -> List (Point3d Meters coordinates)
    -> Plain coordinates
points { radius } givenPoints =
    case givenPoints of
        [] ->
            Types.EmptyMesh

        first :: rest ->
            let
                bounds =
                    BoundingBox3d.hull first rest

                webGLMesh =
                    WebGL.points (List.map plainVertex givenPoints)
            in
            Types.Points bounds (inPixels radius) givenPoints webGLMesh


{-| TODO
-}
shadow : Mesh coordinates attributes -> Shadow coordinates
shadow mesh =
    case mesh of
        Types.EmptyMesh ->
            Types.EmptyShadow

        Types.Triangles boundingBox meshTriangles _ _ ->
            let
                vertexTriples =
                    List.map Triangle3d.vertices meshTriangles
            in
            shadowImpl boundingBox identity (TriangularMesh.triangles vertexTriples)

        Types.Facets boundingBox meshTriangles _ _ ->
            let
                vertexTriples =
                    List.map Triangle3d.vertices meshTriangles
            in
            shadowImpl boundingBox identity (TriangularMesh.triangles vertexTriples)

        Types.Indexed boundingBox triangularMesh _ _ ->
            shadowImpl boundingBox identity triangularMesh

        Types.MeshWithNormals boundingBox triangularMesh _ _ ->
            shadowImpl boundingBox .position triangularMesh

        Types.MeshWithUvs boundingBox triangularMesh _ _ ->
            shadowImpl boundingBox .position triangularMesh

        Types.MeshWithNormalsAndUvs boundingBox triangularMesh _ _ ->
            shadowImpl boundingBox .position triangularMesh

        Types.MeshWithTangents boundingBox triangularMesh _ _ ->
            shadowImpl boundingBox .position triangularMesh

        Types.LineSegments _ _ _ ->
            Types.EmptyShadow

        Types.Polyline _ _ _ ->
            Types.EmptyShadow

        Types.Points _ _ _ _ ->
            Types.EmptyShadow


shadowImpl : BoundingBox3d Meters coordinates -> (a -> Point3d Meters coordinates) -> TriangularMesh a -> Shadow coordinates
shadowImpl meshBounds getPosition triangularMesh =
    let
        meshFaceVertices =
            TriangularMesh.faceVertices triangularMesh

        initialShadowVertices =
            List.foldr (collectShadowVertices getPosition) [] meshFaceVertices

        ( initialShadowFaceIndices, neighborDict, nextShadowVertexIndex ) =
            visitFaces getPosition meshFaceVertices 0 [] Dict.empty

        ( allShadowFaceIndices, extraShadowVertices ) =
            ( initialShadowFaceIndices, [], nextShadowVertexIndex )
                |> joinEdges getPosition neighborDict meshFaceVertices 0

        allShadowVertices =
            if List.isEmpty extraShadowVertices then
                initialShadowVertices

            else
                initialShadowVertices ++ extraShadowVertices
    in
    Types.Shadow meshBounds
        (TriangularMesh.indexed (Array.fromList allShadowVertices) allShadowFaceIndices)
        (WebGL.indexedTriangles allShadowVertices allShadowFaceIndices)


collectShadowVertices :
    (meshVertex -> Point3d Meters coordinates)
    -> ( meshVertex, meshVertex, meshVertex )
    -> List VertexWithNormal
    -> List VertexWithNormal
collectShadowVertices getPosition ( mv1, mv2, mv3 ) accumulated =
    let
        p1 =
            getPosition mv1

        p2 =
            getPosition mv2

        p3 =
            getPosition mv3

        faceNormal =
            Vector3d.toVec3 (triangleNormal p1 p2 p3)

        sv1 =
            { position = Point3d.toVec3 p1, normal = faceNormal }

        sv2 =
            { position = Point3d.toVec3 p2, normal = faceNormal }

        sv3 =
            { position = Point3d.toVec3 p3, normal = faceNormal }
    in
    sv1 :: sv2 :: sv3 :: accumulated


type alias EdgeKey =
    ( ( Float, Float, Float ), ( Float, Float, Float ) )


edgeKey : Point3d Meters coordinates -> Point3d Meters coordinates -> EdgeKey
edgeKey firstPoint secondPoint =
    let
        p1 =
            Point3d.toMeters firstPoint

        p2 =
            Point3d.toMeters secondPoint
    in
    ( ( p1.x, p1.y, p1.z ), ( p2.x, p2.y, p2.z ) )


visitFaces :
    (meshVertex -> Point3d Meters coordinates)
    -> List ( meshVertex, meshVertex, meshVertex )
    -> Int
    -> List ( Int, Int, Int )
    -> Dict EdgeKey Int
    -> ( List ( Int, Int, Int ), Dict EdgeKey Int, Int )
visitFaces getPosition meshFaceVertices nextShadowVertexIndex shadowFaceIndices neighborDict =
    case meshFaceVertices of
        ( mv1, mv2, mv3 ) :: remainingMeshFaceVertices ->
            let
                p1 =
                    getPosition mv1

                p2 =
                    getPosition mv2

                p3 =
                    getPosition mv3

                a =
                    nextShadowVertexIndex

                b =
                    nextShadowVertexIndex + 1

                c =
                    nextShadowVertexIndex + 2

                updatedShadowFaceIndices =
                    ( a, b, c ) :: shadowFaceIndices

                updatedNeighborDict =
                    neighborDict
                        |> Dict.insert (edgeKey p2 p1) a
                        |> Dict.insert (edgeKey p3 p2) b
                        |> Dict.insert (edgeKey p1 p3) c
            in
            visitFaces
                getPosition
                remainingMeshFaceVertices
                (nextShadowVertexIndex + 3)
                updatedShadowFaceIndices
                updatedNeighborDict

        [] ->
            ( shadowFaceIndices, neighborDict, nextShadowVertexIndex )


joinEdges :
    (meshVertex -> Point3d Meters coordinates)
    -> Dict EdgeKey Int
    -> List ( meshVertex, meshVertex, meshVertex )
    -> Int
    -> ( List ( Int, Int, Int ), List VertexWithNormal, Int )
    -> ( List ( Int, Int, Int ), List VertexWithNormal )
joinEdges getPosition neighborDict meshFaceVertices nextShadowVertexIndex state =
    case meshFaceVertices of
        ( mv1, mv2, mv3 ) :: remainingMeshFaceVertices ->
            let
                p1 =
                    getPosition mv1

                p2 =
                    getPosition mv2

                p3 =
                    getPosition mv3

                a =
                    nextShadowVertexIndex

                b =
                    nextShadowVertexIndex + 1

                c =
                    nextShadowVertexIndex + 2
            in
            joinEdges
                getPosition
                neighborDict
                remainingMeshFaceVertices
                (nextShadowVertexIndex + 3)
                (state
                    |> joinEdge p1 p2 a b neighborDict
                    |> joinEdge p2 p3 b c neighborDict
                    |> joinEdge p3 p1 c a neighborDict
                )

        [] ->
            let
                ( shadowFaceIndices, extraShadowVertices, _ ) =
                    state
            in
            ( shadowFaceIndices, List.reverse extraShadowVertices )


zeroVec3 : Vec3
zeroVec3 =
    Math.Vector3.vec3 0 0 0


joinEdge :
    Point3d Meters coordinates
    -> Point3d Meters coordinates
    -> Int
    -> Int
    -> Dict EdgeKey Int
    -> ( List ( Int, Int, Int ), List VertexWithNormal, Int )
    -> ( List ( Int, Int, Int ), List VertexWithNormal, Int )
joinEdge p1 p2 start end neighborDict ( shadowFaceIndices, extraShadowVertices, nextShadowVertexIndex ) =
    case Dict.get (edgeKey p1 p2) neighborDict of
        Just opposite ->
            ( ( start, opposite, end ) :: shadowFaceIndices
            , extraShadowVertices
            , nextShadowVertexIndex
            )

        Nothing ->
            let
                v1 =
                    { position = Point3d.toVec3 p1, normal = zeroVec3 }

                v2 =
                    { position = Point3d.toVec3 p2, normal = zeroVec3 }

                a =
                    nextShadowVertexIndex

                b =
                    nextShadowVertexIndex + 1
            in
            ( ( start, a, b ) :: ( start, b, end ) :: shadowFaceIndices
            , v2 :: v1 :: extraShadowVertices
            , nextShadowVertexIndex + 2
            )


{-| TODO
-}
cullBackFaces : Mesh coordinates attributes -> Mesh coordinates attributes
cullBackFaces mesh =
    case mesh of
        Types.EmptyMesh ->
            mesh

        Types.Triangles boundingBox meshTriangles webGLMesh _ ->
            Types.Triangles boundingBox meshTriangles webGLMesh CullBackFaces

        Types.Facets boundingBox meshTriangles webGLMesh _ ->
            Types.Facets boundingBox meshTriangles webGLMesh CullBackFaces

        Types.Indexed boundingBox triangularMesh webGLMesh _ ->
            Types.Indexed boundingBox triangularMesh webGLMesh CullBackFaces

        Types.MeshWithNormals boundingBox triangularMesh webGLMesh _ ->
            Types.MeshWithNormals boundingBox triangularMesh webGLMesh CullBackFaces

        Types.MeshWithUvs boundingBox triangularMesh webGLMesh _ ->
            Types.MeshWithUvs boundingBox triangularMesh webGLMesh CullBackFaces

        Types.MeshWithNormalsAndUvs boundingBox triangularMesh webGLMesh _ ->
            Types.MeshWithNormalsAndUvs boundingBox triangularMesh webGLMesh CullBackFaces

        Types.MeshWithTangents boundingBox triangularMesh webGLMesh _ ->
            Types.MeshWithTangents boundingBox triangularMesh webGLMesh CullBackFaces

        Types.LineSegments _ _ _ ->
            mesh

        Types.Polyline _ _ _ ->
            mesh

        Types.Points _ _ _ _ ->
            mesh
