module Random where

import System.Random.MWC
import Control.Monad.Primitive

import Data.Array.Accelerate                    as A
import Data.Array.Accelerate.Array.Data         as A
import Data.Array.Accelerate.Array.Sugar        as Sugar

randomArrayIO :: (Shape sh, Elt e) => (sh -> GenIO -> IO e) -> sh -> IO (Array sh e)
randomArrayIO f sh =
  withSystemRandom . asGenIO $ \gen -> do
    seed   <- save gen
    return $! randomArrayOfWithSeed f seed sh

-- | Generate an array of random values using the supplied generator function.
--   The generator for variates is initialised with a fixed seed.
randomArrayOf :: (Shape sh, Elt e) => (sh -> GenIO -> IO e) -> sh -> Array sh e
randomArrayOf f sh
  = let
        n               = Sugar.size sh
        (adata, _)      = runArrayData $ do
                            gen <- create
                            arr <- newArrayData n
                            let write ix = unsafeWriteArrayData arr (Sugar.toIndex sh ix)
                                         . fromElt =<< f ix gen

                            iter sh write (>>) (return ())
                            return (arr, undefined)

    in adata `seq` Array (fromElt sh) adata

-- | Generate an array of random values using a supplied generator function and
--   seed value.
randomArrayOfWithSeed :: (Shape sh, Elt e) => (sh -> GenIO -> IO e) -> Seed -> sh -> Array sh e
randomArrayOfWithSeed f seed sh
  = let
        n               = Sugar.size sh
        (adata, _)      = runArrayData $ do
                            gen <- restore seed
                            arr <- newArrayData n
                            let write ix = unsafeWriteArrayData arr (Sugar.toIndex sh ix)
                                         . fromElt =<< f ix gen

                            iter sh write (>>) (return ())
                            return (arr, undefined)

    in adata `seq` Array (fromElt sh) adata
