{-# LANGUAGE CPP #-}
module Control.Effect.Type.WriterPrim
  ( -- * Effects
    WriterPrim(..)

    -- * Threading utilities
  , threadWriterPrim
  , threadWriterPrimViaClass

    -- * Combinators for 'Algebra's
    -- Intended to be used for custom 'Control.Effect.Carrier' instances when
    -- defining 'algPrims'.
  , algListenPrimIntoWriterPrim
  ) where

import Control.Monad.Trans
import Control.Monad.Trans.Reader (ReaderT)
import Control.Monad.Trans.Except (ExceptT)
import qualified Control.Monad.Trans.State.Strict as SSt
import qualified Control.Monad.Trans.State.Lazy as LSt
import qualified Control.Monad.Trans.Writer.Lazy as LWr
import qualified Control.Monad.Trans.Writer.Strict as SWr
import qualified Control.Monad.Trans.Writer.CPS as CPSWr
import Control.Monad.Writer.Class
import Control.Effect.Internal.ViaAlg
import Control.Effect.Internal.Reflection
import Control.Effect.Internal.Union
import Control.Effect.Type.ListenPrim

-- | A primitive effect that may be used for
-- interpreters of connected 'Control.Effect.Writer.Tell',
-- 'Control.Effect.Writer.Listen', and 'Control.Effect.Writer.Pass' effects.
--
-- This combines 'Control.Effect.Writer.Tell' and
-- 'Control.Effect.Writer.Listen' and 'Control.Effect.Writer.Pass'.
-- This may be relevant if there are monad transformers that may only lift
-- 'Control.Effect.Writer.pass' if they also have access to
-- 'Control.Effect.Writer.listen' and 'Control.Effect.Writer.tell'.
--
-- __'WriterPrim' is only used as a primitive effect.__
-- If you define a 'Control.Effect.Carrier' that relies on a novel
-- non-trivial monad transformer @t@, then you need to make
-- a @'Monoid' w => 'ThreadsEff' t ('WriterPrim' w)@ instance (if possible).
-- 'threadWriterPrim' and 'threadWriterPrimViaClass' can help you with that.
--
-- The following threading constraints accept 'WriterPrim':
--
-- * 'Control.Effect.ReaderThreads'
-- * 'Control.Effect.State.StateThreads'
-- * 'Control.Effect.State.StateLazyThreads'
-- * 'Control.Effect.Error.ErrorThreads'
-- * 'Control.Effect.Writer.WriterThreads'
-- * 'Control.Effect.Writer.WriterLazyThreads'
-- * 'Control.Effect.NonDet.NonDetThreads'
data WriterPrim w m a where
  WriterPrimTell   :: w             -> WriterPrim w m ()
  WriterPrimListen :: m a           -> WriterPrim w m (w, a)
  WriterPrimPass   :: m (w -> w, a) -> WriterPrim w m a

-- | Construct a valid definition of 'threadEff' for a
-- @'ThreadsEff' t ('WriterPrim' w)@ instance only be specifying how
-- 'WriterPrimPass' should be lifted.
--
-- This relies on an existing @'ThreadsEff' t ('ListenPrim' w)@ instance.
threadWriterPrim :: forall w t m a
                  . ( MonadTrans t
                    , ThreadsEff t (ListenPrim w)
                    , Monad m
                    )
                 => ( (forall x. WriterPrim w m x -> m x)
                    -> t m (w -> w, a) -> t m a
                    )
                 -> (forall x. WriterPrim w m x -> m x)
                 -> WriterPrim w (t m) a -> t m a
threadWriterPrim h alg = \case
  WriterPrimTell w   -> lift (alg (WriterPrimTell w))
  WriterPrimListen m -> (`threadEff` (ListenPrimListen m)) $ \case
    ListenPrimTell   w  -> alg (WriterPrimTell w)
    ListenPrimListen m' -> alg (WriterPrimListen m')
  WriterPrimPass m -> h alg m
{-# INLINE threadWriterPrim #-}

instance ( Reifies s (ReifiedEffAlgebra (WriterPrim w) m)
         , Monoid w
         , Monad m
         )
      => MonadWriter w (ViaAlg s (WriterPrim w) m) where
  tell w = case reflect @s of
    ReifiedEffAlgebra alg -> coerceAlg alg (WriterPrimTell w)
  {-# INLINE tell #-}

  listen m = case reflect @s of
    ReifiedEffAlgebra alg ->
      fmap (\(s, a) -> (a, s)) $ coerceAlg alg (WriterPrimListen m)
  {-# INLINE listen #-}

  pass m = case reflect @s of
    ReifiedEffAlgebra alg ->
      coerceAlg alg (WriterPrimPass (fmap (\(a,f) -> (f, a)) m))
  {-# INLINE pass #-}

-- | A valid definition of 'threadEff' for a
-- @'Monoid' w => 'ThreadsEff' ('WriterPrim' w) t@ instance,
-- given that @t@ lifts @'MonadWriter' w@.
threadWriterPrimViaClass :: forall w t m a
                          . (Monoid w, MonadTrans t, Monad m)
                         => ( RepresentationalT t
                            , forall b. MonadWriter w b => MonadWriter w (t b)
                            )
                         => (forall x. WriterPrim w m x -> m x)
                         -> WriterPrim w (t m) a -> t m a
threadWriterPrimViaClass alg = \case
  WriterPrimTell w   -> lift (alg (WriterPrimTell w))
  WriterPrimListen m ->
    reify (ReifiedEffAlgebra alg) $ \(_ :: pr s) ->
        unViaAlgT
      $ fmap (\(f, a) -> (a, f))
      $ listen
      $ viaAlgT @s @(WriterPrim w) m
  WriterPrimPass m ->
    reify (ReifiedEffAlgebra alg) $ \(_ :: pr s) ->
        unViaAlgT
      $ pass
      $ fmap (\(f, a) -> (a, f))
      $ viaAlgT @s @(WriterPrim w) m
{-# INLINE threadWriterPrimViaClass #-}

#define THREAD_WRITERPRIM(monadT)                              \
instance Monoid threadedMonoid                                 \
      => ThreadsEff (monadT) (WriterPrim threadedMonoid) where \
  threadEff = threadWriterPrimViaClass;                        \
  {-# INLINE threadEff #-}

THREAD_WRITERPRIM(ReaderT i)
THREAD_WRITERPRIM(ExceptT e)
THREAD_WRITERPRIM(LSt.StateT s)
THREAD_WRITERPRIM(SSt.StateT s)

instance Monoid s => ThreadsEff (LWr.WriterT s) (WriterPrim w) where
  threadEff = threadWriterPrim $ \alg m ->
      LWr.WriterT
    $ alg
    $ WriterPrimPass
    $ fmap (\((f,a), s) -> (f, (a, s)))
    $ LWr.runWriterT m
  {-# INLINE threadEff #-}

instance Monoid s => ThreadsEff (SWr.WriterT s) (WriterPrim w) where
  threadEff = threadWriterPrim $ \alg m ->
      SWr.WriterT
    $ alg
    $ WriterPrimPass
    $ fmap (\((f,a), s) -> (f, (a, s)))
    $ SWr.runWriterT m
  {-# INLINE threadEff #-}

instance Monoid s => ThreadsEff (CPSWr.WriterT s) (WriterPrim w) where
  threadEff = threadWriterPrim $ \alg m ->
      CPSWr.writerT
    $ alg
    $ WriterPrimPass
    $ fmap (\((f,a), s) -> (f, (a, s)))
    $ CPSWr.runWriterT m
  {-# INLINE threadEff #-}

-- | Rewrite an 'Algebra' where the topmost effect is 'ListenPrim' into
-- an 'Algebra' where the topmost effect is 'WriterPrim' by providing
-- an implementation of 'WriterPrimPass'.
algListenPrimIntoWriterPrim :: Algebra' (ListenPrim w ': p) m a
                            -> (m (w -> w, a) -> m a)
                            -> Algebra' (WriterPrim w ': p) m a
algListenPrimIntoWriterPrim alg h = powerAlg (weakenAlg alg) $ \case
  WriterPrimTell w   -> (alg . inj) (ListenPrimTell w)
  WriterPrimListen m -> (alg . inj) (ListenPrimListen m)
  WriterPrimPass m   -> h m
{-# INLINE algListenPrimIntoWriterPrim #-}
