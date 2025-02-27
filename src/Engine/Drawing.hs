{-# LANGUAGE CPP #-}

#ifndef __HLINT__

module Engine.Drawing where

import Control.Monad (void)
import Data.Foldable (for_, traverse_)
import Engine.Camera (viaCamera)
import Engine.FRP
import Engine.Geometry (rectContains)
import Engine.Globals (global_resources, global_sprites, global_glyphs, global_textures, global_songs, global_sounds)
import Engine.Types
import Engine.Utils (originRectToRect)
import Foreign.C
import Game.Resources (frameSound, frameCounts)
import SDL
import SDL.Mixer


playSound :: Sound -> IO ()
playSound s = do
  let channel = fromIntegral $ fromEnum s
  halt channel
  void $ playOn channel Once $ global_sounds s


drawOriginRect :: Color -> OriginRect Double -> V2 WorldPos -> Renderable
drawOriginRect c ore = drawFilledRect c . originRectToRect (coerce ore)


drawFilledRect :: Color -> Rectangle WorldPos -> Renderable
drawFilledRect c (Rectangle (P v) sz) cam = do
  let rect' = Rectangle (P $ viaCamera cam v) $ coerce sz
  let renderer = e_renderer $ r_engine global_resources
  rendererDrawColor renderer $= c
  fillRect renderer $ Just $ fmap (round . getScreenPos) rect'

drawBackgroundColor :: Color -> Renderable
drawBackgroundColor c _ = do
  let renderer = e_renderer $ r_engine global_resources
  rendererDrawColor renderer $= c
  fillRect renderer Nothing

drawSpriteStretched
    :: WrappedTexture  -- ^ Texture
    -> V2 WorldPos       -- ^ position
    -> Double          -- ^ rotation in rads
    -> V2 Bool         -- ^ mirroring
    -> V2 Double       -- ^ scaling factor
    -> Renderable
drawSpriteStretched wt pos theta flips stretched cam
  | let wp = viaCamera cam $ pos - coerce (fmap fromIntegral (wt_origin wt) * stretched)
  , rectContains screenRect wp
  = do
      let renderer = e_renderer $ r_engine global_resources
      copyEx
        renderer
        (getTexture wt)
        (wt_sourceRect wt)
        (Just $ fmap round
              $ Rectangle (P $ coerce wp)
              $ fmap fromIntegral (wt_size wt) * stretched)
        (CDouble theta)
        (Just $ fmap round
              $ P
              $ fmap fromIntegral (wt_origin wt) * stretched)
        flips
  | otherwise = mempty

drawGameTextureOriginRect
    :: GameTexture
    -> OriginRect Double
    -> V2 WorldPos     -- ^ position
    -> Double          -- ^ rotation in rads
    -> V2 Bool         -- ^ mirroring
    -> Renderable
drawGameTextureOriginRect = drawTextureOriginRect . global_textures

drawTextureOriginRect
    :: WrappedTexture  -- ^ Texture
    -> OriginRect Double
    -> V2 WorldPos     -- ^ position
    -> Double          -- ^ rotation in rads
    -> V2 Bool         -- ^ mirroring
    -> Renderable
drawTextureOriginRect wt ore pos theta flips cam
  | let wp = viaCamera cam pos
  , rectContains screenRect wp
  = do
      let renderer = e_renderer $ r_engine global_resources
      copyEx
        renderer
        (getTexture wt)
        (wt_sourceRect wt)
        (Just $ fmap round $ originRectToRect ore $ coerce wp)
        (CDouble theta)
        (Just $ P $ fmap round $ orect_offset ore)
        flips
  | otherwise = mempty

drawSprite
    :: WrappedTexture
    -> V2 WorldPos  -- ^ pos
    -> Double     -- ^ rotation in rads
    -> V2 Bool    -- ^ mirroring
    -> Renderable
drawSprite wt pos theta flips =
  drawSpriteStretched wt pos theta flips 1

playSong :: Song -> IO ()
playSong s = do
  playMusic Forever (global_songs s)

mkAnim :: Sprite -> SF (DrawSpriteDetails, V2 WorldPos) Renderable
mkAnim sprite = proc (dsd, pos) -> do
  let anim = dsd_anim dsd
  global_tick <- round . (/ 0.1) <$> localTime -< ()
  new_anim <- onChange -< dsd_anim dsd
  anim_start <- hold 0 -< global_tick <$ new_anim

  let anim_frame = (global_tick - anim_start) `mod` frameCounts sprite anim
  new_frame <- onChange -< anim_frame

  returnA -< \cam -> do
    for_ new_frame $ traverse_ playSound . frameSound sprite anim
    drawSprite
      (global_sprites sprite anim !! anim_frame)
      pos
      (dsd_rotation dsd)
      (dsd_flips dsd)
      cam


atScreenPos :: Renderable -> Renderable
atScreenPos f _ = f $ Camera 0


drawText :: Double -> V3 Word8 -> String -> V2 WorldPos -> Renderable
drawText sz color text pos@(V2 x y) cam
  | rectContains screenRect $ viaCamera cam pos
  = do
      let renderer = e_renderer $ r_engine global_resources
      for_ (zip text [0..]) $ \(c, i) -> do
        let glyph = global_glyphs c
        textureColorMod glyph $= color
        copy renderer glyph Nothing
          $ Just
          $ fmap round
          $ Rectangle (P $ coerce $ viaCamera cam $ V2 (x + coerce (i * sz)) y)
          $ V2 sz sz
      rendererDrawBlendMode renderer $= BlendAlphaBlend
  | otherwise = mempty

drawParallax :: V2 WorldPos -> GameTexture -> Double -> Renderable
drawParallax sz gt scale c@(Camera cam) =
  flip atScreenPos c
    $ drawTextureOriginRect (global_textures gt) (coerce bg_ore) (logicalSize / 2) 0
    $ pure False
  where
    perc = coerce $ -cam / sz
    bg_ore = OriginRect (logicalSize ^* scale) ((logicalSize ^* scale) * perc)

#endif
