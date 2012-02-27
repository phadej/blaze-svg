{-# LANGUAGE CPP #-}

#define DO_NOT_EDIT (doNotEdit __FILE__ __LINE__)

-- | Generates code for SVG tags.
--
module Util.GenerateSvgCombinators where

import Control.Arrow ((&&&))
import Data.List (sort, sortBy, intersperse, intercalate)
import Data.Ord (comparing)
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>), (<.>))
import Data.Map (Map)
import qualified Data.Map as M
import Data.Char (toLower)
import qualified Data.Set as S

import Util.Sanitize (sanitize, prelude)

-- | Datatype for an SVG variant.
--
data SvgVariant = SvgVariant
    { version     :: [String]
    , docType     :: [String]
    , parents     :: [String]
    , leafs       :: [String]
    , attributes  :: [String]
    , selfClosing :: Bool
    } deriving (Eq)

instance Show SvgVariant where
    show = map toLower . intercalate "-" . version

-- | Get the full module name for an SVG variant.
--
getModuleName :: SvgVariant -> String
getModuleName = ("Text.Blaze." ++) . intercalate "." . version

-- | Get the attribute module name for an SVG variant.
--
getAttributeModuleName :: SvgVariant -> String
getAttributeModuleName = (++ ".Attributes") . getModuleName

-- | Check if a given name causes a name clash.
--
isNameClash :: SvgVariant -> String -> Bool
isNameClash v t
    -- Both an element and an attribute
    | (t `elem` parents v || t `elem` leafs v) && t `elem` attributes v = True
    -- Already a prelude function
    | sanitize t `S.member` prelude = True
    | otherwise = False

-- | Write an SVG variant.
--
writeSvgVariant :: SvgVariant -> IO ()
writeSvgVariant svgVariant = do
    -- Make a directory.
    createDirectoryIfMissing True basePath

    let tags =  zip parents' (repeat makeParent)
             ++ zip leafs' (repeat (makeLeaf $ selfClosing svgVariant))
        sortedTags = sortBy (comparing fst) tags
        appliedTags = map (\(x, f) -> f x) sortedTags

    -- Write the main module.
    writeFile' (basePath <.> "hs") $ removeTrailingNewlines $ unlines
        [ DO_NOT_EDIT
        , "{-# LANGUAGE OverloadedStrings #-}"
        , "-- | This module exports SVG combinators used to create documents."
        , "--"
        , exportList modulName $ "module Text.Blaze"
                                : "module Text.Blaze.Svg"
                                : "docType"
                                : "docTypeSvg"
                                : map (sanitize . fst) sortedTags
        , DO_NOT_EDIT
        , "import Prelude ((>>), (.), ($))"
        , ""
        , "import Text.Blaze"
        , "import Text.Blaze.Svg"
        , "import Text.Blaze.Internal"
        , ""
        , makeDocType $ docType svgVariant
        , makeDocTypeSvg $ docType svgVariant
        , unlines appliedTags
        ]

    let sortedAttributes = sort attributes'

    -- Write the attribute module.
    writeFile' (basePath </> "Attributes.hs") $ removeTrailingNewlines $ unlines
        [ DO_NOT_EDIT
        , "-- | This module exports combinators that provide you with the"
        , "-- ability to set attributes on SVG elements."
        , "--"
        , "{-# LANGUAGE OverloadedStrings #-}"
        , exportList attributeModuleName $ map sanitize sortedAttributes
        , DO_NOT_EDIT
        , "import Prelude ()"
        , ""
        , "import Text.Blaze.Internal (Attribute, AttributeValue, attribute)"
        , ""
        , unlines (map makeAttribute sortedAttributes)
        ]
  where
    basePath = "Text" </> "Blaze" </> foldl1 (</>) version'
    modulName = getModuleName svgVariant
    attributeModuleName = getAttributeModuleName svgVariant
    attributes' = attributes svgVariant
    parents'    = parents svgVariant
    leafs'      = leafs svgVariant
    version'    = version svgVariant
    removeTrailingNewlines = reverse . drop 2 . reverse
    writeFile' file content = do
        putStrLn ("Generating " ++ file)
        writeFile file content

-- | Create a string, consisting of @x@ spaces, where @x@ is the length of the
-- argument.
--
spaces :: String -> String
spaces = flip replicate ' ' . length

-- | Join blocks of code with a newline in between.
--
unblocks :: [String] -> String
unblocks = unlines . intersperse "\n"

-- | A warning to not edit the generated code.
--
doNotEdit :: FilePath -> Int -> String
doNotEdit fileName lineNumber = init $ unlines
    [ "-- WARNING: The next block of code was automatically generated by"
    , "-- " ++ fileName ++ ":" ++ show lineNumber
    , "--"
    ]

-- | Generate an export list for a Haskell module.
--
exportList :: String   -- ^ Module name.
           -> [String] -- ^ List of functions.
           -> String   -- ^ Resulting string.
exportList _    []            = error "exportList without functions."
exportList name (f:functions) = unlines $
    [ "module " ++ name
    , "    ( " ++ f
    ] ++
    map ("    , " ++) functions ++
    [ "    ) where"]

-- | Generate a function for a doctype.
--
makeDocType :: [String] -> String
makeDocType lines' = unlines
    [ DO_NOT_EDIT
    , "-- | Combinator for the document type. This should be placed at the top"
    , "-- of every SVG page."
    , "--"
    , unlines (map ("-- > " ++) lines') ++ "--"
    , "docType :: Svg  -- ^ The document type SVG."
    , "docType = preEscapedText " ++ show (unlines lines')
    , "{-# INLINE docType #-}"
    ]

-- | Generate a function for the SVG tag (including the doctype).
--
makeDocTypeSvg :: [String]  -- ^ The doctype.
                -> String    -- ^ Resulting combinator function.
makeDocTypeSvg lines' = unlines
    [ DO_NOT_EDIT
    , "-- | Combinator for the @\\<svg>@ element. This combinator will also"
    , "-- insert the correct doctype."
    , "--"
    , unlines (map ("-- > " ++) lines') ++ "-- > <svg><span>foo</span></svg>"
    , "--"
    , "docTypeSvg :: Svg  -- ^ Inner SVG."
    , "            -> Svg  -- ^ Resulting SVG."
    , "docTypeSvg inner = docType >> (svg ! attribute \"xmlns\" \" xmlns=\\\"\" \"http://www.w3.org/2000/svg\" ! attribute \"xmlns:xlink\" \" xmlns:xlink=\\\"\" \"http://www.w3.org/1999/xlink\"  $ inner)"
    , "{-# INLINE docTypeSvg #-}"
    ]

-- | Generate a function for an SVG tag that can be a parent.
--
makeParent :: String -> String
makeParent tag = unlines
    [ DO_NOT_EDIT
    , "-- | Combinator for the @\\<" ++ tag ++ ">@ element."
    , "--"
    , function        ++ " :: Svg  -- ^ Inner SVG."
    , spaces function ++ " -> Svg  -- ^ Resulting SVG."
    , function        ++ " = Parent \"" ++ tag ++ "\" \"<" ++ tag
                      ++ "\" \"</" ++ tag ++ ">\"" ++ modifier
    , "{-# INLINE " ++ function ++ " #-}"
    ]
  where
    function = sanitize tag
    modifier = if tag `elem` ["style", "script"] then " . external" else ""

-- | Generate a function for an SVG tag that must be a leaf.
--
makeLeaf :: Bool    -- ^ Make leaf tags self-closing
         -> String  -- ^ Tag for the combinator
         -> String  -- ^ Combinator code
makeLeaf closing tag = unlines
    [ DO_NOT_EDIT
    , "-- | Combinator for the @\\<" ++ tag ++ " />@ element."
    , "--"
    , function ++ " :: Svg  -- ^ Resulting SVG."
    , function ++ " = Leaf \"" ++ tag ++ "\" \"<" ++ tag ++ "\" " ++ "\""
               ++ (if closing then " /" else "") ++ ">\""
    , "{-# INLINE " ++ function ++ " #-}"
    ]
  where
    function = sanitize tag

-- | Generate a function for an SVG attribute.
--
makeAttribute :: String -> String
makeAttribute name = unlines
    [ DO_NOT_EDIT
    , "-- | Combinator for the @" ++ name ++ "@ attribute."
    , "--"
    , function        ++ " :: AttributeValue  -- ^ Attribute value."
    , spaces function ++ " -> Attribute       -- ^ Resulting attribute."
    , function        ++ " = attribute \"" ++ name ++ "\" \" "
                      ++ name ++ "=\\\"\""
    , "{-# INLINE " ++ function ++ " #-}"
    ]
  where
    function = sanitize name

-- | SVG 1.1
-- Reference: https://developer.mozilla.org/en/SVG
--
svg11 :: SvgVariant
svg11 = SvgVariant
    { version = ["Svg11"]
    , docType =
        [ "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
        , "<!DOCTYPE svg PUBLIC \"-//W3C//DTD SVG 1.1//EN\""
        , "    \"http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd\">"
        ]
    , parents =
        [ "a","defs","glyph","g","marker","mask","missing-glyph","pattern", "svg"
        , "switch", "symbol"
        ]
    , leafs =
        [ "altGlyph", "altGlyphDef", "altGlyphItem", "animate", "animateColor"
        , "animateMotion", "animateTransform", "circle", "clipPath"
        , "color-profile" , "cursor", "desc", "ellipse", "feBlend"
        , "feColorMatrix", "feComponentTransfer" , "feComposite"
        , "feConvolveMatrix", "feDiffuseLighting", "feDisplacementMap"
        , "feDistantLight", "feFlood", "feFuncA", "feFuncB" , "feFuncG"
        , "feFuncR", "feGaussianBlur", "feImage", "feMerge", "feMergeNode"
        , "feMorphology", "feOffset", "fePointLight", "feSpecularLighting"
        , "feSpotLight" , "feTile", "feTurbulence", "filter", "font"
        , "font-face", "font-face-format" , "font-face-name", "font-face-src"
        , "font-face-uri", "foreignObject" , "glyphRef", "hkern", "image"
        , "line", "linearGradient" , "metadata", "mpath", "path"
        , "polygon" , "polyline", "radialGradient", "rect", "script", "set"
        , "stop", "style" , "text", "textPath", "title", "tref", "tspan", "use"
        , "view", "vkern"
        ]
    , attributes =
        [ "accent-height", "accumulate", "additive", "alphabetic", "amplitude"
        , "arabic-form", "ascent", "attributeName", "attributeType", "azimuth"
        , "baseFrequency", "baseProfile", "bbox", "begin", "bias", "by", "calcMode"
        , "cap-height", "class", "clipPathUnits", "contentScriptType"
        , "contentStyleType", "cx", "cy", "d", "descent", "diffuseConstant", "divisor"
        , "dur", "dx", "dy", "edgeMode", "elevation", "end", "exponent"
        , "externalResourcesRequired", "fill", "filterRes", "filterUnits", "font-family"
        , "font-size", "font-stretch", "font-style", "font-variant", "font-weight"
        , "format", "from", "fx", "fy", "g1", "g2", "glyph-name", "glyphRef"
        , "gradientTransform", "gradientUnits", "hanging", "height", "horiz-adv-x"
        , "horiz-origin-x", "horiz-origin-y", "id", "ideographic", "in", "in2"
        , "intercept", "k", "k1", "k2", "k3", "k4", "kernelMatrix", "kernelUnitLength"
        , "keyPoints", "keySplines", "keyTimes", "lang", "lengthAdjust"
        , "limitingConeAngle", "local", "markerHeight", "markerUnits", "markerWidth"
        , "maskContentUnits", "maskUnits", "mathematical", "max", "media", "method"
        , "min", "mode", "name", "numOctaves", "offset", "onabort", "onactivate"
        , "onbegin", "onclick", "onend", "onerror", "onfocusin", "onfocusout", "onload"
        , "onmousedown", "onmousemove", "onmouseout", "onmouseover", "onmouseup"
        , "onrepeat", "onresize", "onscroll", "onunload", "onzoom", "operator", "order"
        , "orient", "orientation", "origin", "overline-position", "overline-thickness"
        , "panose-1", "path", "pathLength", "patternContentUnits", "patternTransform"
        , "patternUnits", "points", "pointsAtX", "pointsAtY", "pointsAtZ"
        , "preserveAlpha", "preserveAspectRatio", "primitiveUnits", "r", "radius"
        , "refX", "refY", "rendering-intent", "repeatCount", "repeatDur"
        , "requiredExtensions", "requiredFeatures", "restart", "result", "rotate", "rx"
        , "ry", "scale", "seed", "slope", "spacing", "specularConstant"
        , "specularExponent", "spreadMethod", "startOffset", "stdDeviation", "stemh"
        , "stemv", "stitchTiles", "strikethrough-position", "strikethrough-thickness"
        , "string", "style", "surfaceScale", "systemLanguage", "tableValues", "target"
        , "targetX", "targetY", "textLength", "title", "to", "transform", "type", "u1"
        , "u2", "underline-position", "underline-thickness", "unicode", "unicode-range"
        , "units-per-em", "v-alphabetic", "v-hanging", "v-ideographic", "v-mathematical"
        , "values", "version", "vert-adv-y", "vert-origin-x", "vert-origin-y", "viewBox"
        , "viewTarget", "width", "widths", "x", "x-height", "x1", "x2"
        , "xChannelSelector", "xlink:actuate", "xlink:arcrole", "xlink:href"
        , "xlink:role", "xlink:show", "xlink:title", "xlink:type", "xml:base"
        , "xml:lang", "xml:space", "y", "y1", "y2", "yChannelSelector", "z", "zoomAndPan"
        -- Presentation Attributes
        , "alignment-baseline", "baseline-shift", "clip-path", "clip-rule"
        , "clip", "color-interpolation-filters", "color-interpolation"
        , "color-profile", "color-rendering", "color", "cursor", "direction"
        , "display", "dominant-baseline", "enable-background", "fill-opacity"
        , "fill-rule", "filter", "flood-color", "flood-opacity"
        , "font-size-adjust", "glyph-orientation-horizontal"
        , "glyph-orientation-vertical", "image-rendering", "kerning", "letter-spacing"
        , "lighting-color", "marker-end", "marker-mid", "marker-start", "mask"
        , "opacity", "overflow", "pointer-events", "shape-rendering", "stop-color"
        , "stop-opacity", "stroke-dasharray", "stroke-dashoffset", "stroke-linecap"
        , "stroke-linejoin", "stroke-miterlimit", "stroke-opacity", "stroke-width"
        , "stroke", "text-anchor", "text-decoration", "text-rendering", "unicode-bidi"
        , "visibility", "word-spacing", "writing-mode"
        ]
    , selfClosing = True
    }

-- | A map of SVG variants, per version, lowercase.
--
svgVariants :: Map String SvgVariant
svgVariants = M.fromList $ map (show &&& id)
    [ svg11 ]

main :: IO ()
main = mapM_ (writeSvgVariant . snd) $ M.toList svgVariants
