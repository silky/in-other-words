{-# LANGUAGE CPP, TupleSections #-}
{-# OPTIONS_HADDOCK not-home #-}
module Control.Effect.Type.Optional where

import Data.Functor.Const
import Control.Effect.Internal.Union
import Control.Effect.Type.Regional
import Control.Monad.Trans.Reader (ReaderT(..), mapReaderT)
import Control.Monad.Trans.Except (ExceptT(..), mapExceptT)
import qualified Control.Monad.Trans.State.Strict as SSt
import qualified Control.Monad.Trans.State.Lazy as LSt
import qualified Control.Monad.Trans.Writer.Lazy as LWr
import qualified Control.Monad.Trans.Writer.Strict as SWr
import qualified Control.Monad.Trans.Writer.CPS as CPSWr


-- | A /helper primitive effect/ for manipulating a region, with the option
-- to execute it in full or in part.
--
-- Helper primitive effects are effects that allow you to avoid interpreting one
-- of your own effects as a primitive if the power needed from direct access to
-- the underlying monad can instead be provided by the relevant helper primitive
-- effect. The reason why you'd want to do this is that helper primitive effects
-- already have 'ThreadsEff' instances defined for them, so you don't have to
-- define any for your own effect.
--
-- The helper primitive effects offered in this library are - in ascending
-- levels of power - 'Regional', 'Optional', 'BaseControl' and 'Unlift'.
--
-- The typical use-case of 'Regional' is to lift a natural transformation
-- of a base monad equipped with the power to recover from an exception.
-- 'Control.Effect.HoistOption' and accompaning interpreters is
-- provided as a specialization of 'Optional' for this purpose.
--
-- 'Optional' in its most general form lacks a pre-defined interpreter:
-- when not using 'Control.Effect.HoistOption', you're expected to define your
-- own interpreter for 'Optional' (treating it as a primitive effect).
-- Note that when used as a primitive effect, @s@ is expected to be a functor.
--
-- **'Optional' is typically used as a primitive effect.**
-- If you define a 'Control.Effect.Carrier' that relies on a novel
-- non-trivial monad transformer, then you need to make a
-- a @Functor s => 'ThreadsEff' ('Optional' s)@ instance for that monad
-- transformer (if possible). 'Control.Effect.Optional.threadOptionalViaBaseControl'
-- can help you with that.
data Optional s m a where
  Optional :: s a -> m a -> Optional s m a

-- | A valid definition of 'threadEff' for a @'ThreadsEff' ('Regional' s) t@ instance,
-- given that @t@ threads @'Optional' f@ for any functor @f@.
threadRegionalViaOptional :: ( ThreadsEff (Optional (Const s)) t
                             , Monad m)
                          => (forall x. Regional s m x -> m x)
                          -> Regional s (t m) a -> t m a
threadRegionalViaOptional alg (Regional s m) =
  threadEff
    (\(Optional (Const s') m') -> alg (Regional s' m'))
    (Optional (Const s) m)
{-# INLINE threadRegionalViaOptional #-}

instance Functor s => ThreadsEff (Optional s) (ExceptT e) where
  threadEff alg (Optional sa m) = mapExceptT (alg . Optional (fmap Right sa)) m
  {-# INLINE threadEff #-}

instance ThreadsEff (Optional s) (ReaderT i) where
  threadEff alg (Optional sa m) = mapReaderT (alg . Optional sa) m
  {-# INLINE threadEff #-}

instance Functor s => ThreadsEff (Optional s) (SSt.StateT s') where
  threadEff alg (Optional sa m) = SSt.StateT $ \s ->
    alg $ Optional (fmap (, s) sa) (SSt.runStateT m s)
  {-# INLINE threadEff #-}

instance Functor s => ThreadsEff (Optional s) (LSt.StateT s') where
  threadEff alg (Optional sa m) = LSt.StateT $ \s ->
    alg $ Optional (fmap (, s) sa) (LSt.runStateT m s)
  {-# INLINE threadEff #-}

instance (Functor s, Monoid w) => ThreadsEff (Optional s) (LWr.WriterT w) where
  threadEff alg (Optional sa m) =
    LWr.mapWriterT (alg . Optional (fmap (, mempty) sa)) m
  {-# INLINE threadEff #-}

instance (Functor s, Monoid w) => ThreadsEff (Optional s) (SWr.WriterT w) where
  threadEff alg (Optional sa m) =
    SWr.mapWriterT (alg . Optional (fmap (, mempty) sa)) m
  {-# INLINE threadEff #-}

instance (Functor s, Monoid w)
      => ThreadsEff (Optional s) (CPSWr.WriterT w) where
  threadEff alg (Optional sa m) =
    CPSWr.mapWriterT (alg . Optional (fmap (, mempty) sa)) m
  {-# INLINE threadEff #-}