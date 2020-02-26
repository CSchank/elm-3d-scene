module Scene3d exposing
    ( toHtml
    , Option
    , multisampling, supersampling, dynamicRange
    , Entity
    , nothing, quad, block, sphere, cylinder, mesh, group
    , shadow, withShadow
    , rotateAround, translateBy, translateIn, scaleAbout, mirrorAcross
    , placeIn, relativeTo
    , transparentBackground, whiteBackground, blackBackground, backgroundColor, transparentBackgroundColor
    , defaultExposure, defaultWhiteBalance
    , LightSource, directionalLight, pointLight
    , CastsShadows, Yes, No, castsShadows, doesNotCastShadows
    , DirectLighting, noDirectLighting, oneLightSource, twoLightSources, threeLightSources, fourLightSources, fiveLightSources, sixLightSources, sevenLightSources, eightLightSources
    , EnvironmentalLighting, noEnvironmentalLighting, softLighting
    , toWebGLEntities
    )

{-|

@docs toHtml


# Options

@docs Option

@docs multisampling, supersampling, dynamicRange


# Entities

@docs Entity

@docs nothing, quad, block, sphere, cylinder, mesh, group


# Shadows

@docs shadow, withShadow


# Transformations

These transformations are 'cheap' in that they don't actually transform the
underlying mesh; under the hood they use a WebGL [transformation matrix](https://learnopengl.com/Getting-started/Transformations)
to change where that mesh gets rendered.

@docs rotateAround, translateBy, translateIn, scaleAbout, mirrorAcross


# Coordinate conversions

You're unlikely to need these functions right away but they can be very useful
when setting up more complex scenes.

@docs placeIn, relativeTo


# Background

@docs transparentBackground, whiteBackground, blackBackground, backgroundColor, transparentBackgroundColor


# Default rendering values

@docs defaultExposure, defaultWhiteBalance


# Lighting

Lighting in `elm-3d-scene` is a combination of _direct_ and _environmental_
(indirect, ambient) lighting. Direct lighting comes from specific light sources
like the sun or a light bulb; you can currently have up to eight separate light
sources in a scene. Environmental lighting accounts for light coming from all
around an object; for example, if you are outside, you might be getting direct
light from the sun but you're also getting light reflected from other surfaces
around you. Generally, direct lighting gives nice highlights but can be very
harsh; it's usually best to use a combination of one or more direct lights plus
some soft indirect lighting.


## Direct lighting

@docs LightSource, directionalLight, pointLight

@docs CastsShadows, Yes, No, castsShadows, doesNotCastShadows

@docs DirectLighting, noDirectLighting, oneLightSource, twoLightSources, threeLightSources, fourLightSources, fiveLightSources, sixLightSources, sevenLightSources, eightLightSources


## Environmental lighting

@docs EnvironmentalLighting, noEnvironmentalLighting, softLighting


# Advanced

@docs toWebGLEntities

-}

import Angle exposing (Angle)
import Axis3d exposing (Axis3d)
import Block3d exposing (Block3d)
import Camera3d exposing (Camera3d)
import Color exposing (Color)
import Color.Transparent
import Cylinder3d exposing (Cylinder3d)
import Direction3d exposing (Direction3d)
import Frame3d exposing (Frame3d)
import Geometry.Interop.LinearAlgebra.Frame3d as Frame3d
import Geometry.Interop.LinearAlgebra.Point3d as Point3d
import Html exposing (Html)
import Html.Attributes
import Html.Keyed
import Illuminance exposing (Illuminance)
import Length exposing (Length, Meters)
import Luminance exposing (Luminance)
import LuminousFlux exposing (LuminousFlux)
import Math.Matrix4 exposing (Mat4)
import Math.Vector3 exposing (Vec3)
import Math.Vector4 exposing (Vec4)
import Pixels exposing (Pixels, inPixels)
import Plane3d exposing (Plane3d)
import Point3d exposing (Point3d)
import Quantity exposing (Quantity(..))
import Rectangle2d
import Scene3d.Chromaticity as Chromaticity exposing (Chromaticity)
import Scene3d.ColorConversions as ColorConversions
import Scene3d.Entity as Entity
import Scene3d.Exposure as Exposure exposing (Exposure)
import Scene3d.Material as Material exposing (Material)
import Scene3d.Mesh as Mesh exposing (Mesh)
import Scene3d.Transformation as Transformation exposing (Transformation)
import Scene3d.Types as Types exposing (DrawFunction, LightMatrices, LinearRgb(..), Material(..), Node(..))
import Sphere3d exposing (Sphere3d)
import Vector3d exposing (Vector3d)
import Viewpoint3d
import WebGL
import WebGL.Settings
import WebGL.Settings.DepthTest as DepthTest
import WebGL.Settings.StencilTest as StencilTest
import WebGL.Texture exposing (Texture)



----- ENTITIES -----


{-| An `Entity` is a shape or group of shapes in a scene.
-}
type alias Entity coordinates =
    Types.Entity coordinates


{-| A dummy entity for which nothing will be drawn.
-}
nothing : Entity coordinates
nothing =
    Entity.empty


quad :
    CastsShadows a
    -> Material.Textured coordinates
    -> Point3d Meters coordinates
    -> Point3d Meters coordinates
    -> Point3d Meters coordinates
    -> Point3d Meters coordinates
    -> Entity coordinates
quad (CastsShadows shadowFlag) givenMaterial p1 p2 p3 p4 =
    Entity.quad shadowFlag givenMaterial p1 p2 p3 p4


{-| Draw a sphere using the [`Sphere3d`](https://package.elm-lang.org/packages/ianmackenzie/elm-geometry/latest/Sphere3d)
type from `elmm-geometry`.

The sphere will have texture (UV) coordinates based on an [equirectangular
projection](https://wiki.panotools.org/Equirectangular_Projection) where
positive Z is up. This sounds complex but really just means that U corresponds
to angle around the sphere and V corresponds to angle up the sphere, similar to
the diagrams shown [here](https://en.wikipedia.org/wiki/Spherical_coordinate_system)
except that V is measured up from the bottom (negative Z) instead of down from
the top (positive Z).

Note that this projection, while simple, maeans that the texture used will get
'squished' near the poles of the sphere.

-}
sphere : CastsShadows a -> Material.Textured coordinates -> Sphere3d Meters coordinates -> Entity coordinates
sphere (CastsShadows shadowFlag) givenMaterial givenSphere =
    Entity.sphere shadowFlag givenMaterial givenSphere


block : CastsShadows a -> Material.Uniform coordinates -> Block3d Meters coordinates -> Entity coordinates
block (CastsShadows shadowFlag) givenMaterial givenBlock =
    Entity.block shadowFlag givenMaterial givenBlock


cylinder : CastsShadows a -> Material.Uniform coordinates -> Cylinder3d Meters coordinates -> Entity coordinates
cylinder (CastsShadows shadowFlag) givenMaterial givenCylinder =
    Entity.cylinder shadowFlag givenMaterial givenCylinder


{-| Draw the given mesh with the given material.
-}
mesh : Material coordinates attributes -> Mesh coordinates attributes -> Entity coordinates
mesh givenMaterial givenMesh =
    Entity.mesh givenMaterial givenMesh


{-| Group a list of entities into a single entity. This entity can then be
transformed, grouped with other entities, etc.
-}
group : List (Entity coordinates) -> Entity coordinates
group entities =
    Entity.group entities


{-| Draw the _shadow_ of an object. Note that this means you can choose to
render an object and its shadow, and object without its shadow, or even render
an object's shadow without the object itself for [maximum creepiness](https://en.wikipedia.org/wiki/Identity_Crisis_(Star_Trek:_The_Next_Generation)).
-}
shadow : Mesh.Shadow coordinates -> Entity coordinates
shadow givenShadow =
    Entity.shadow givenShadow


{-| Convenience function for rendering an object and its shadow;

    Scene3d.withShadow shadow entity

is shorthand for

    Scene3d.group [ entity, Scene3d.shadow shadow ]

-}
withShadow : Mesh.Shadow coordinates -> Entity coordinates -> Entity coordinates
withShadow givenShadow givenEntity =
    group [ givenEntity, shadow givenShadow ]


{-| Rotate an entity around a given axis by a given angle.
-}
rotateAround : Axis3d Meters coordinates -> Angle -> Entity coordinates -> Entity coordinates
rotateAround axis angle entity =
    Entity.rotateAround axis angle entity


{-| Translate (move) an entity by a given displacement vector.
-}
translateBy : Vector3d Meters coordinates -> Entity coordinates -> Entity coordinates
translateBy displacement entity =
    Entity.translateBy displacement entity


{-| Translate an entity in a given direction by a given distance.
-}
translateIn : Direction3d coordinates -> Length -> Entity coordinates -> Entity coordinates
translateIn direction distance entity =
    Entity.translateIn direction distance entity


{-| Scale an entity about a given point by a given scale. The given point will
remain fixed in place and all other points on the entity will be stretched away
from that point (or contract towards that point, if the scale is less than one).

`elm-3d-scene` tries very hard to do the right thing here even if you use a
_negative_ scale factor, but that flips the mesh inside out so I don't really
recommend it.

-}
scaleAbout : Point3d Meters coordinates -> Float -> Entity coordinates -> Entity coordinates
scaleAbout centerPoint scale entity =
    Entity.scaleAbout centerPoint scale entity


{-| Mirror an entity across a plane.
-}
mirrorAcross : Plane3d Meters coordinates -> Entity coordinates -> Entity coordinates
mirrorAcross plane entity =
    Entity.mirrorAcross plane entity


{-| Take an entity that is defined in a local coordinate system and convert it
to global coordinates. This can be useful if you have some entities which are
defined in some local coordinate system like inside a car, and you want to
render them within a larger world.
-}
placeIn : Frame3d Meters coordinates { defines : localCoordinates } -> Entity localCoordinates -> Entity coordinates
placeIn frame entity =
    Entity.placeIn frame entity


{-| Take an entity that is defined in global coordinates and convert into a
local coordinate system. This is even less likely to be useful than `placeIn`,
but may be useful if you are (for example) rendering an office scene (and
working primarily in local room coordinates) but want to incorporate some entity
defined in global coordinates like a bird flying past the window.
-}
relativeTo : Frame3d Meters coordinates { defines : localCoordinates } -> Entity coordinates -> Entity localCoordinates
relativeTo frame entity =
    Entity.relativeTo frame entity



----- LIGHT SOURCES -----
--
-- type:
--   0 : disabled
--   1 : directional (XYZ is direction to light, i.e. reversed light direction)
--   2 : point (XYZ is light position)
--
-- radius is unused for now (will hopefully add sphere lights in the future)
--
-- [ x_i     r_i       x_j     r_j      ]
-- [ y_i     g_i       y_j     g_j      ]
-- [ z_i     b_i       z_j     b_j      ]
-- [ type_i  radius_i  type_j  radius_j ]


{-| A `LightSource` represents a single source of light in the scene, such as
the sun or a light bulb. Light sources are not rendered themselves; they can
only be seen by how they interact with entities (meshes).
-}
type alias LightSource coordinates castsShadows =
    Types.LightSource coordinates castsShadows


type DirectLighting coordinates
    = SingleUnshadowedPass LightMatrices
    | SingleShadowedPass LightMatrices
    | TwoPasses LightMatrices LightMatrices


disabledLightSource : LightSource coordinates castsShadows
disabledLightSource =
    Types.LightSource
        { type_ = 0
        , castsShadows = False
        , x = 0
        , y = 0
        , z = 0
        , r = 0
        , g = 0
        , b = 0
        , radius = 0
        }


lightSourcePair : LightSource coordinates firstCastsShadows -> LightSource coordinates secondCastsShadows -> Mat4
lightSourcePair (Types.LightSource first) (Types.LightSource second) =
    Math.Matrix4.fromRecord
        { m11 = first.x
        , m21 = first.y
        , m31 = first.z
        , m41 = first.type_
        , m12 = first.r
        , m22 = first.g
        , m32 = first.b
        , m42 = first.radius
        , m13 = second.x
        , m23 = second.y
        , m33 = second.z
        , m43 = second.type_
        , m14 = second.r
        , m24 = second.g
        , m34 = second.b
        , m44 = second.radius
        }


lightingDisabled : LightMatrices
lightingDisabled =
    { lightSources12 = lightSourcePair disabledLightSource disabledLightSource
    , lightSources34 = lightSourcePair disabledLightSource disabledLightSource
    , lightSources56 = lightSourcePair disabledLightSource disabledLightSource
    , lightSources78 = lightSourcePair disabledLightSource disabledLightSource
    }


noDirectLighting : DirectLighting coordinates
noDirectLighting =
    SingleUnshadowedPass lightingDisabled


lightCastsShadows : LightSource coordinates castsShadows -> Bool
lightCastsShadows (Types.LightSource properties) =
    properties.castsShadows


oneLightSource : LightSource coordinates (CastsShadows a) -> DirectLighting coordinates
oneLightSource lightSource =
    let
        lightMatrices =
            { lightSources12 = lightSourcePair lightSource disabledLightSource
            , lightSources34 = lightSourcePair disabledLightSource disabledLightSource
            , lightSources56 = lightSourcePair disabledLightSource disabledLightSource
            , lightSources78 = lightSourcePair disabledLightSource disabledLightSource
            }
    in
    if lightCastsShadows lightSource then
        SingleShadowedPass lightMatrices

    else
        SingleUnshadowedPass lightMatrices


twoLightSources :
    LightSource coordinates (CastsShadows a)
    -> LightSource coordinates (CastsShadows No)
    -> DirectLighting coordinates
twoLightSources first second =
    eightLightSources
        first
        second
        disabledLightSource
        disabledLightSource
        disabledLightSource
        disabledLightSource
        disabledLightSource
        disabledLightSource


threeLightSources :
    LightSource coordinates (CastsShadows a)
    -> LightSource coordinates (CastsShadows No)
    -> LightSource coordinates (CastsShadows No)
    -> DirectLighting coordinates
threeLightSources first second third =
    eightLightSources
        first
        second
        third
        disabledLightSource
        disabledLightSource
        disabledLightSource
        disabledLightSource
        disabledLightSource


fourLightSources :
    LightSource coordinates (CastsShadows a)
    -> LightSource coordinates (CastsShadows No)
    -> LightSource coordinates (CastsShadows No)
    -> LightSource coordinates (CastsShadows No)
    -> DirectLighting coordinates
fourLightSources first second third fourth =
    eightLightSources
        first
        second
        third
        fourth
        disabledLightSource
        disabledLightSource
        disabledLightSource
        disabledLightSource


fiveLightSources :
    LightSource coordinates (CastsShadows a)
    -> LightSource coordinates (CastsShadows No)
    -> LightSource coordinates (CastsShadows No)
    -> LightSource coordinates (CastsShadows No)
    -> LightSource coordinates (CastsShadows No)
    -> DirectLighting coordinates
fiveLightSources first second third fourth fifth =
    eightLightSources
        first
        second
        third
        fourth
        fifth
        disabledLightSource
        disabledLightSource
        disabledLightSource


sixLightSources :
    LightSource coordinates (CastsShadows a)
    -> LightSource coordinates (CastsShadows No)
    -> LightSource coordinates (CastsShadows No)
    -> LightSource coordinates (CastsShadows No)
    -> LightSource coordinates (CastsShadows No)
    -> LightSource coordinates (CastsShadows No)
    -> DirectLighting coordinates
sixLightSources first second third fourth fifth sixth =
    eightLightSources
        first
        second
        third
        fourth
        fifth
        sixth
        disabledLightSource
        disabledLightSource


sevenLightSources :
    LightSource coordinates (CastsShadows a)
    -> LightSource coordinates (CastsShadows No)
    -> LightSource coordinates (CastsShadows No)
    -> LightSource coordinates (CastsShadows No)
    -> LightSource coordinates (CastsShadows No)
    -> LightSource coordinates (CastsShadows No)
    -> LightSource coordinates (CastsShadows No)
    -> DirectLighting coordinates
sevenLightSources first second third fourth fifth sixth seventh =
    eightLightSources
        first
        second
        third
        fourth
        fifth
        sixth
        seventh
        disabledLightSource


eightLightSources :
    LightSource coordinates (CastsShadows a)
    -> LightSource coordinates (CastsShadows No)
    -> LightSource coordinates (CastsShadows No)
    -> LightSource coordinates (CastsShadows No)
    -> LightSource coordinates (CastsShadows No)
    -> LightSource coordinates (CastsShadows No)
    -> LightSource coordinates (CastsShadows No)
    -> LightSource coordinates (CastsShadows No)
    -> DirectLighting coordinates
eightLightSources first second third fourth fifth sixth seventh eigth =
    if lightCastsShadows first then
        TwoPasses
            { lightSources12 = lightSourcePair first second
            , lightSources34 = lightSourcePair third fourth
            , lightSources56 = lightSourcePair fifth sixth
            , lightSources78 = lightSourcePair seventh eigth
            }
            { lightSources12 = lightSourcePair second third
            , lightSources34 = lightSourcePair fourth fifth
            , lightSources56 = lightSourcePair sixth seventh
            , lightSources78 = lightSourcePair eigth disabledLightSource
            }

    else
        SingleUnshadowedPass
            { lightSources12 = lightSourcePair first second
            , lightSources34 = lightSourcePair third fourth
            , lightSources56 = lightSourcePair fifth sixth
            , lightSources78 = lightSourcePair seventh eigth
            }


type CastsShadows a
    = CastsShadows Bool


type Yes
    = Yes


type No
    = No


castsShadows : CastsShadows Yes
castsShadows =
    CastsShadows True


doesNotCastShadows : CastsShadows No
doesNotCastShadows =
    CastsShadows False


directionalLight :
    CastsShadows a
    ->
        { chromaticity : Chromaticity
        , intensity : Illuminance
        , direction : Direction3d coordinates
        }
    -> LightSource coordinates (CastsShadows a)
directionalLight (CastsShadows shadowFlag) { chromaticity, intensity, direction } =
    let
        { x, y, z } =
            Direction3d.unwrap direction

        (LinearRgb rgb) =
            ColorConversions.chromaticityToLinearRgb chromaticity

        lux =
            Illuminance.inLux intensity
    in
    Types.LightSource
        { type_ = 1
        , castsShadows = shadowFlag
        , x = -x
        , y = -y
        , z = -z
        , r = lux * Math.Vector3.getX rgb
        , g = lux * Math.Vector3.getY rgb
        , b = lux * Math.Vector3.getZ rgb
        , radius = 0
        }


pointLight :
    CastsShadows a
    ->
        { chromaticity : Chromaticity
        , intensity : LuminousFlux
        , position : Point3d Meters coordinates
        }
    -> LightSource coordinates (CastsShadows a)
pointLight (CastsShadows shadowFlag) { chromaticity, intensity, position } =
    let
        (LinearRgb rgb) =
            ColorConversions.chromaticityToLinearRgb chromaticity

        lumens =
            LuminousFlux.inLumens intensity

        { x, y, z } =
            Point3d.unwrap position
    in
    Types.LightSource
        { type_ = 2
        , castsShadows = shadowFlag
        , x = x
        , y = y
        , z = z
        , r = lumens * Math.Vector3.getX rgb
        , g = lumens * Math.Vector3.getY rgb
        , b = lumens * Math.Vector3.getZ rgb
        , radius = 0
        }



----- ENVIRONMENTAL LIGHTING ------


type alias EnvironmentalLighting coordinates =
    Types.EnvironmentalLighting coordinates


environmentalLightingDisabled : Mat4
environmentalLightingDisabled =
    Math.Matrix4.fromRecord
        { m11 = 0
        , m21 = 0
        , m31 = 0
        , m41 = 0
        , m12 = 0
        , m22 = 0
        , m32 = 0
        , m42 = 0
        , m13 = 0
        , m23 = 0
        , m33 = 0
        , m43 = 0
        , m14 = 0
        , m24 = 0
        , m34 = 0
        , m44 = 0
        }


noEnvironmentalLighting : EnvironmentalLighting coordinates
noEnvironmentalLighting =
    Types.NoEnvironmentalLighting


{-| Good default value for max luminance: 5000 nits
-}
softLighting :
    { upDirection : Direction3d coordinates
    , above : ( Luminance, Chromaticity )
    , below : ( Luminance, Chromaticity )
    }
    -> EnvironmentalLighting coordinates
softLighting { upDirection, above, below } =
    let
        { x, y, z } =
            Direction3d.unwrap upDirection

        ( aboveLuminance, aboveChromaticity ) =
            above

        ( belowLuminance, belowChromaticity ) =
            below

        aboveNits =
            Luminance.inNits aboveLuminance

        belowNits =
            Luminance.inNits belowLuminance

        (LinearRgb aboveRgb) =
            ColorConversions.chromaticityToLinearRgb aboveChromaticity

        (LinearRgb belowRgb) =
            ColorConversions.chromaticityToLinearRgb belowChromaticity
    in
    Types.SoftLighting <|
        Math.Matrix4.fromRecord
            { m11 = x
            , m21 = y
            , m31 = z
            , m41 = 1
            , m12 = aboveNits * Math.Vector3.getX aboveRgb
            , m22 = aboveNits * Math.Vector3.getY aboveRgb
            , m32 = aboveNits * Math.Vector3.getZ aboveRgb
            , m42 = 0
            , m13 = belowNits * Math.Vector3.getX belowRgb
            , m23 = belowNits * Math.Vector3.getY belowRgb
            , m33 = belowNits * Math.Vector3.getZ belowRgb
            , m43 = 0
            , m14 = 0
            , m24 = 0
            , m34 = 0
            , m44 = 0
            }



----- BACKGROUND -----


type Background
    = BackgroundColor Color.Transparent.Color


transparentBackground : Background
transparentBackground =
    BackgroundColor <|
        Color.Transparent.fromRGBA
            { red = 0
            , green = 0
            , blue = 0
            , alpha = Color.Transparent.transparent
            }


blackBackground : Background
blackBackground =
    BackgroundColor <|
        Color.Transparent.fromRGBA
            { red = 0
            , green = 0
            , blue = 0
            , alpha = Color.Transparent.opaque
            }


whiteBackground : Background
whiteBackground =
    BackgroundColor <|
        Color.Transparent.fromRGBA
            { red = 255
            , green = 255
            , blue = 255
            , alpha = Color.Transparent.opaque
            }


backgroundColor : Color -> Background
backgroundColor color =
    BackgroundColor (Color.Transparent.fromColor Color.Transparent.opaque color)


transparentBackgroundColor : Color.Transparent.Color -> Background
transparentBackgroundColor transparentColor =
    BackgroundColor transparentColor



----- DEFAULTS -----


defaultExposure : Exposure
defaultExposure =
    Exposure.srgb


defaultWhiteBalance : Chromaticity
defaultWhiteBalance =
    Chromaticity.d65



----- RENDERING -----


type alias RenderPass =
    LightMatrices -> List WebGL.Settings.Setting -> WebGL.Entity


type alias RenderPasses =
    { meshes : List RenderPass
    , shadows : List RenderPass
    , points : List RenderPass
    }


createRenderPass : Mat4 -> Mat4 -> Mat4 -> Transformation -> DrawFunction -> RenderPass
createRenderPass sceneProperties viewMatrix ambientLightingMatrix transformation drawFunction =
    let
        normalSign =
            if transformation.isRightHanded then
                1

            else
                -1

        modelScale =
            Math.Vector4.vec4
                transformation.scaleX
                transformation.scaleY
                transformation.scaleZ
                normalSign
    in
    drawFunction
        sceneProperties
        modelScale
        (Transformation.modelMatrix transformation)
        transformation.isRightHanded
        viewMatrix
        ambientLightingMatrix


collectRenderPasses : Mat4 -> Mat4 -> Mat4 -> Transformation -> Node -> RenderPasses -> RenderPasses
collectRenderPasses sceneProperties viewMatrix ambientLightingMatrix currentTransformation node accumulated =
    case node of
        EmptyNode ->
            accumulated

        Transformed transformation childNode ->
            collectRenderPasses
                sceneProperties
                viewMatrix
                ambientLightingMatrix
                (Transformation.compose transformation currentTransformation)
                childNode
                accumulated

        MeshNode meshDrawFunction ->
            let
                updatedMeshes =
                    createRenderPass
                        sceneProperties
                        viewMatrix
                        ambientLightingMatrix
                        currentTransformation
                        meshDrawFunction
                        :: accumulated.meshes
            in
            { meshes = updatedMeshes
            , shadows = accumulated.shadows
            , points = accumulated.points
            }

        PointNode pointDrawFunction ->
            let
                updatedPoints =
                    createRenderPass
                        sceneProperties
                        viewMatrix
                        ambientLightingMatrix
                        currentTransformation
                        pointDrawFunction
                        :: accumulated.points
            in
            { meshes = accumulated.meshes
            , shadows = accumulated.shadows
            , points = updatedPoints
            }

        ShadowNode shadowDrawFunction ->
            let
                updatedShadows =
                    createRenderPass
                        sceneProperties
                        viewMatrix
                        ambientLightingMatrix
                        currentTransformation
                        shadowDrawFunction
                        :: accumulated.shadows
            in
            { meshes = accumulated.meshes
            , shadows = updatedShadows
            , points = accumulated.points
            }

        Group childNodes ->
            List.foldl
                (collectRenderPasses
                    sceneProperties
                    viewMatrix
                    ambientLightingMatrix
                    currentTransformation
                )
                accumulated
                childNodes



-- ## Overall scene Properties
--
-- projectionType:
--   0: perspective (camera XYZ is eye position)
--   1: orthographic (camera XYZ is direction to screen)
--
-- [ clipDistance  cameraX         whiteR        supersampling ]
-- [ aspectRatio   cameraY         whiteG        *             ]
-- [ kc            cameraZ         whiteB        *             ]
-- [ kz            projectionType  dynamicRange  *             ]


depthTestDefault : List WebGL.Settings.Setting
depthTestDefault =
    [ DepthTest.default ]


outsideStencil : List WebGL.Settings.Setting
outsideStencil =
    [ DepthTest.lessOrEqual { write = True, near = 0, far = 1 }
    , StencilTest.test
        { ref = 0
        , mask = 0xFF
        , test = StencilTest.equal
        , fail = StencilTest.keep
        , zfail = StencilTest.keep
        , zpass = StencilTest.keep
        , writeMask = 0x00
        }
    ]


insideStencil : List WebGL.Settings.Setting
insideStencil =
    [ DepthTest.lessOrEqual { write = True, near = 0, far = 1 }
    , StencilTest.test
        { ref = 0
        , mask = 0xFF
        , test = StencilTest.notEqual
        , fail = StencilTest.keep
        , zfail = StencilTest.keep
        , zpass = StencilTest.keep
        , writeMask = 0x00
        }
    ]


createShadowStencil : List WebGL.Settings.Setting
createShadowStencil =
    -- Note that the actual stencil test is added by each individual shadow
    -- entity (in Scene3d.Entity.shadowSettings) since the exact test to perform
    -- depends on whether the current model matrix is right-handed or
    -- left-handed
    [ DepthTest.less { write = False, near = 0, far = 1 }
    , WebGL.Settings.colorMask False False False False
    ]


call : List RenderPass -> LightMatrices -> List WebGL.Settings.Setting -> List WebGL.Entity
call renderPasses lightMatrices settings =
    renderPasses
        |> List.map (\renderPass -> renderPass lightMatrices settings)


toWebGLEntities :
    { directLighting : DirectLighting coordinates
    , environmentalLighting : EnvironmentalLighting coordinates
    , camera : Camera3d Meters coordinates
    , exposure : Exposure
    , dynamicRange : Float
    , whiteBalance : Chromaticity
    , aspectRatio : Float
    , supersampling : Float
    }
    -> List (Entity coordinates)
    -> List WebGL.Entity
toWebGLEntities arguments drawables =
    let
        projectionParameters =
            Camera3d.projectionParameters
                { screenAspectRatio = arguments.aspectRatio }
                arguments.camera

        clipDistance =
            Math.Vector4.getX projectionParameters

        kc =
            Math.Vector4.getZ projectionParameters

        kz =
            Math.Vector4.getW projectionParameters

        eyePoint =
            Camera3d.viewpoint arguments.camera
                |> Viewpoint3d.eyePoint
                |> Point3d.unwrap

        projectionType =
            if kz == 0 then
                0

            else
                1

        (LinearRgb linearRgb) =
            ColorConversions.chromaticityToLinearRgb arguments.whiteBalance

        maxLuminance =
            Luminance.inNits (Exposure.maxLuminance arguments.exposure)

        sceneProperties =
            Math.Matrix4.fromRecord
                { m11 = clipDistance
                , m21 = arguments.aspectRatio
                , m31 = kc
                , m41 = kz
                , m12 = eyePoint.x
                , m22 = eyePoint.y
                , m32 = eyePoint.z
                , m42 = projectionType
                , m13 = maxLuminance * Math.Vector3.getX linearRgb
                , m23 = maxLuminance * Math.Vector3.getY linearRgb
                , m33 = maxLuminance * Math.Vector3.getZ linearRgb
                , m43 = arguments.dynamicRange
                , m14 = arguments.supersampling
                , m24 = 0
                , m34 = 0
                , m44 = 0
                }

        viewMatrix =
            Camera3d.viewMatrix arguments.camera

        environmentalLightingMatrix =
            case arguments.environmentalLighting of
                Types.SoftLighting matrix ->
                    matrix

                Types.NoEnvironmentalLighting ->
                    environmentalLightingDisabled

        (Types.Entity rootNode) =
            Entity.group drawables

        renderPasses =
            collectRenderPasses
                sceneProperties
                viewMatrix
                environmentalLightingMatrix
                Transformation.identity
                rootNode
                { meshes = []
                , shadows = []
                , points = []
                }
    in
    case arguments.directLighting of
        SingleUnshadowedPass lightMatrices ->
            List.concat
                [ call renderPasses.meshes lightMatrices depthTestDefault
                , call renderPasses.points lightingDisabled depthTestDefault
                ]

        SingleShadowedPass lightMatrices ->
            List.concat
                [ call renderPasses.meshes lightingDisabled depthTestDefault
                , call renderPasses.shadows lightMatrices createShadowStencil
                , call renderPasses.meshes lightMatrices outsideStencil
                , call renderPasses.points lightingDisabled depthTestDefault
                ]

        TwoPasses allLightMatrices unshadowedLightMatrices ->
            List.concat
                [ call renderPasses.meshes allLightMatrices depthTestDefault
                , call renderPasses.shadows allLightMatrices createShadowStencil
                , call renderPasses.meshes unshadowedLightMatrices insideStencil
                , call renderPasses.points lightingDisabled depthTestDefault
                ]


toHtml :
    List Option
    ->
        { directLighting : DirectLighting coordinates
        , environmentalLighting : EnvironmentalLighting coordinates
        , camera : Camera3d Meters coordinates
        , exposure : Exposure
        , whiteBalance : Chromaticity
        , dimensions : ( Quantity Float Pixels, Quantity Float Pixels )
        , background : Background
        }
    -> List (Entity coordinates)
    -> Html msg
toHtml options arguments drawables =
    let
        ( width, height ) =
            arguments.dimensions

        widthInPixels =
            inPixels width

        heightInPixels =
            inPixels height

        (BackgroundColor givenBackgroundColor) =
            arguments.background

        backgroundColorString =
            Color.Transparent.toRGBAString givenBackgroundColor

        optionValues =
            collectOptionValues options

        commonWebGLOptions =
            [ WebGL.depth 1
            , WebGL.stencil 0
            , WebGL.alpha True
            , WebGL.clearColor 0 0 0 0
            ]

        webGLOptions =
            if optionValues.multisampling then
                WebGL.antialias :: commonWebGLOptions

            else
                commonWebGLOptions

        -- Force WebGL context to be recreated if multisampling option changes
        key =
            if optionValues.multisampling then
                "1"

            else
                "0"

        widthCss =
            Html.Attributes.style "width" (String.fromFloat widthInPixels ++ "px")

        heightCss =
            Html.Attributes.style "height" (String.fromFloat heightInPixels ++ "px")
    in
    Html.Keyed.node "div" [ Html.Attributes.style "padding" "0px", widthCss, heightCss ] <|
        [ ( key
          , WebGL.toHtmlWith webGLOptions
                [ Html.Attributes.width (round (widthInPixels * optionValues.supersampling))
                , Html.Attributes.height (round (heightInPixels * optionValues.supersampling))
                , widthCss
                , heightCss
                , Html.Attributes.style "display" "block"
                , Html.Attributes.style "background-color" backgroundColorString
                ]
                (toWebGLEntities
                    { directLighting = arguments.directLighting
                    , environmentalLighting = arguments.environmentalLighting
                    , camera = arguments.camera
                    , exposure = arguments.exposure
                    , dynamicRange = optionValues.dynamicRange
                    , whiteBalance = arguments.whiteBalance
                    , aspectRatio = Quantity.ratio width height
                    , supersampling = optionValues.supersampling
                    }
                    drawables
                )
          )
        ]


type Option
    = Multisampling Bool
    | Supersampling Float
    | DynamicRange Float


multisampling : Bool -> Option
multisampling =
    Multisampling


supersampling : Float -> Option
supersampling =
    Supersampling


dynamicRange : Float -> Option
dynamicRange =
    DynamicRange


type alias OptionValues =
    { multisampling : Bool
    , supersampling : Float
    , dynamicRange : Float
    }


defaultOptionValues : OptionValues
defaultOptionValues =
    { multisampling = True
    , supersampling = 1
    , dynamicRange = 1
    }


collectOptionValues : List Option -> OptionValues
collectOptionValues options =
    List.foldl setOption defaultOptionValues options


setOption : Option -> OptionValues -> OptionValues
setOption option currentValues =
    case option of
        Multisampling value ->
            { currentValues | multisampling = value }

        Supersampling value ->
            { currentValues | supersampling = value }

        DynamicRange value ->
            { currentValues | dynamicRange = value }
