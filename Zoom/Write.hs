{-# LANGUAGE RecordWildCards #-}
{-# OPTIONS -Wall #-}

module Zoom.Write (
      Zoom
    , ZoomState(..)

    -- * State initialisation
    , zoomOpenW
    , zoomWithFileW

    -- * Data injection
    , zoomPutInt
    , zoomPutDouble
    
    , zoomFlush

    , zoomClose
) where

import Blaze.ByteString.Builder
import Control.Monad.State
import qualified Data.ByteString as BS
import Data.Monoid
import Data.Word
import System.IO
import Unsafe.Coerce (unsafeCoerce)

------------------------------------------------------------

(<>) :: Builder -> Builder -> Builder
(<>) = mappend

data ZoomState = ZoomState
    { zoomHandle  :: Handle
    , zoomBuilder :: Builder
    , zoomPending :: Int
    }

type Zoom = StateT ZoomState IO

zoomOpenW :: FilePath -> IO ZoomState
zoomOpenW path = do
    h <- openFile path WriteMode
    return (ZoomState h mempty 0)

zoomWithFileW :: FilePath -> Zoom () -> IO ()
zoomWithFileW path f = do
    z <- zoomOpenW path
    z' <- execStateT f z
    zoomClose z'

zoomIncPending :: Zoom ()
zoomIncPending = do
    p <- gets zoomPending
    if (p >= 1024) 
        then do
            z <- get
            z' <- liftIO $ zoomFlush z
            put $ z' { zoomPending = 0 }
        else
            modify $ \z -> z { zoomPending = p+1 }

zoomPutInt :: Int -> Zoom ()
zoomPutInt d = do
    zoomIncPending
    modify $ \z -> z { zoomBuilder = zoomBuilder z <> (fromInt32le . fromIntegral) d }

zoomPutDouble :: Double -> Zoom ()
zoomPutDouble d = do
    zoomIncPending
    modify $ \z -> z { zoomBuilder = zoomBuilder z <> (fromWord64be . toWord64) d }

zoomFlush :: ZoomState -> IO ZoomState
zoomFlush z@ZoomState{..} = do
    toByteStringIO (BS.hPut zoomHandle) zoomBuilder
    return z { zoomBuilder = mempty }
    
zoomClose :: ZoomState -> IO ()
zoomClose z@ZoomState{..} = do
    _ <- zoomFlush z
    hClose zoomHandle

toWord64 :: Double -> Word64
toWord64 = unsafeCoerce

