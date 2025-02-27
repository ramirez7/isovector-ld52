{-# OPTIONS_GHC -Wno-orphans #-}

module Game.Objects.Player where

import           Engine.Collision (epsilon)
import           Control.Lens ((*~))
import           Data.Monoid
import qualified Data.Set as S
import           Engine.Drawing
import           FRP.Yampa ((*^))
import           Game.Common
import           Game.Objects.Actor (actor)
import           Game.Objects.Particle (gore)
import           Game.Objects.TeleportBall (teleportBall)
import qualified SDL.Vect as SDL

player :: V2 WorldPos -> Object
player pos0 = proc oi -> do
  -- TODO(sandy): this is a bad pattern; object constructor should take an
  -- initial pos
  start <- nowish () -< ()
  let pos = event (os_pos $ oi_state oi) (const pos0) start

  let am_teleporting
        = fmap (foldMap (foldMap (Endo . const) . preview #_TeleportTo . snd))
        . oie_receive
        $ oi_events oi

      do_teleport :: V2 WorldPos -> V2 WorldPos
      do_teleport = event id appEndo am_teleporting

  reset <- edge -< c_reset $ fi_controls $ oi_frameInfo oi
  let cp_hit = listenInbox (\(from, m) -> (from, ) <$> preview #_SetCheckpoint m) $ oi_events oi
  cp_pos <- hold pos0 -< fmap snd cp_hit

  let dying = merge reset
            $ listenInbox (preview #_Die . snd)
            $ oi_events oi


      doorout :: Maybe (V2 WorldPos)
      doorout = eventToMaybe
              $ listenInbox (preview #_TeleportOpportunity . snd)
              $ oi_events oi

      tramp :: Maybe Double
      tramp = eventToMaybe
              $ listenInbox (preview #_OnTrampoline . snd)
              $ oi_events oi

      powerups :: S.Set PowerupType
      powerups = gs_inventory $ gameState oi

  (alive, respawn, death_evs) <- dieAndRespawnHandler -< (pos, dying)

  let me = oi_self oi
  action <- edge -< c_z $ fi_controls $ oi_frameInfo oi
  let throw_ball = bool noEvent action $ S.member PowerupWarpBall powerups

  let can_double_jump = S.member PowerupDoubleJump powerups
      dt = fi_dt $ oi_frameInfo oi
  vel'0 <- playerPhysVelocity -< oi_frameInfo oi
  pos' <- actor ore -<
    ( can_double_jump
    , dt
    , vel'0 & _y %~ maybe id const tramp
    , pos
    , fi_global $ oi_frameInfo oi
    )

  let (V2 _ press_up) = fmap (== -1) $ c_dir $ fi_controls $ oi_frameInfo oi
  let pos'' = bool (const pos) id alive
          $ bool id (const cp_pos) (isEvent respawn)
          $ bool id (maybe id const doorout) press_up
          $ do_teleport
          $ pos'

  edir <- edgeBy diffDir 0 -< pos
  dir <- hold True -< edir

  let V2 _ updowndir = c_dir $ fi_controls $ oi_frameInfo oi

  drawn <- drawPlayer -< pos''

  returnA -<
    ObjectOutput
        { oo_events = (death_evs <>) $
            mempty
              & #oe_spawn .~
                  ([teleportBall me ore pos (- (sz & _x .~ 0))
                      $ V2 (bool negate id dir 200) (-200)] <$ throw_ball
                  )
              & #oe_focus .~ mconcat
                  [ () <$ am_teleporting
                  , start
                  ]
              & #oe_broadcast_message .~ fmap (pure . CurrentCheckpoint . fst) cp_hit
        , oo_state =
            oi_state oi
              & #os_pos .~ pos''
              & #os_camera_offset .~ V2 (bool negate id dir 80 * max 0.3 (1 - abs (fromIntegral updowndir)))
                                        (case updowndir of
                                           -1 -> -100
                                           0 -> -50
                                           1 -> 75
                                           _ -> error "impossible: player cam"
                                        )
              & #os_collision .~ bool Nothing (Just ore) alive
              & #os_tags %~ S.insert IsPlayer
        , oo_render = ifA alive drawn
        }
  where
    ore = OriginRect sz $ sz & _x *~ 0.5

    sz :: Num a => V2 a
    sz = V2 8 16


respawnTime :: Time
respawnTime = 1


dieAndRespawnHandler :: SF (V2 WorldPos, Event ()) (Bool, Event (), ObjectEvents)
dieAndRespawnHandler = proc (pos, on_die) -> do
  t <- time -< ()
  let next_alive = t + respawnTime
  respawn_at <- hold 0 -< next_alive <$ on_die

  let alive = respawn_at <= t
  let actually_die = bool noEvent on_die $ respawn_at == next_alive

  respawn <- edge -< respawn_at <= t

  returnA -< (alive, respawn, ) $ mempty
    & #oe_spawn .~ (gore pos <$ actually_die)
    & #oe_play_sound .~ ([DieSound] <$ actually_die)


playerPhysVelocity :: SF FrameInfo (V2 Double)
playerPhysVelocity = proc fi -> do
  let jumpVel = V2 0 (-210)
  let stepSpeed = 10
  jumpEv <- edge -< c_space (fi_controls fi)
  let jump = event 0 (const jumpVel) jumpEv
  let vx = V2 stepSpeed 0 * (realToFrac <$> c_dir (fi_controls fi))
  let vy = jump
  let vel' = vx + vy
  returnA -< vel'


drawPlayer :: SF (V2 WorldPos) Renderable
drawPlayer = arr mconcat <<< fork
  [ proc pos -> do
      -- We can fully animate the player as a function of the position!
      edir <- edgeBy diffDir 0 -< pos
      dir <- hold True -< edir
      V2 vx vy <- derivative -< pos
      mkAnim MainCharacter
        -<  ( DrawSpriteDetails
                (bool Idle Run $ abs vx >= epsilon && abs vy < epsilon)
                0
                (V2 (not dir) False)
            , pos
            )
  ]


instance (Floating a, Eq a) => VectorSpace (V2 a) a where
  zeroVector = 0
  (*^) = (Game.Common.*^)
  (^+^) = (+)
  dot = SDL.dot


diffDir :: ( Ord a, Floating a) =>V2 a -> V2 a -> Maybe Bool
diffDir (V2 old _) (V2 new _) =
  case abs (old - new) <= epsilon of
    True -> Nothing
    False -> Just $ new > old

