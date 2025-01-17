-- | Here be unutterable, atrocious, ungodly dragons
module Engine.Globals where

import Data.IORef
import Engine.Types
import Game.Resources (loadResources)
import SDL (Texture)
import SDL.Mixer (Chunk, Music)
import System.IO.Unsafe

veryUnsafeEngineIORef :: IORef Engine
veryUnsafeEngineIORef = unsafePerformIO $ newIORef $ error "no unsafe engine io ref"
{-# NOINLINE veryUnsafeEngineIORef #-}

global_resources :: Resources
global_resources = unsafePerformIO $ loadResources =<< readIORef veryUnsafeEngineIORef
{-# NOINLINE global_resources #-}

global_textures :: GameTexture -> WrappedTexture
global_sounds :: Sound -> Chunk
global_songs :: Song -> Music
global_worlds :: WorldName -> World
global_sprites :: Sprite -> Anim -> [WrappedTexture]
global_glyphs :: Char -> Texture

Resources
  { r_textures = global_textures
  , r_sounds   = global_sounds
  , r_worlds   = global_worlds
  , r_sprites  = global_sprites
  , r_glyphs   = global_glyphs
  , r_songs    = global_songs
  } = global_resources


{-# NOINLINE global_textures #-}
{-# NOINLINE global_sounds   #-}
{-# NOINLINE global_worlds   #-}
{-# NOINLINE global_sprites  #-}
{-# NOINLINE global_glyphs  #-}
{-# NOINLINE global_songs  #-}

