{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE OverloadedStrings #-}

module Flags2Env
  ( parse
  , parseFromFile
  , parseProcess
  , parseProcessFromFile
  , apply
  ) where

import Data.Aeson (eitherDecodeStrict', encode)
import qualified Data.ByteString.Char8 as BS
import qualified Data.ByteString.Lazy as BL
import qualified Data.Map.Strict as Map
import Data.Map.Strict (Map)
import Data.Text (Text)
import Foreign.C.String (CString, peekCString, withCString)
import Foreign.Ptr (nullPtr)
import Control.Monad ((>=>))

foreign import ccall unsafe "f2e_parse_json_argv"
  c_parse_json_argv :: CString -> IO CString

foreign import ccall unsafe "f2e_parse_json_argv_from_file"
  c_parse_json_argv_from_file :: CString -> CString -> IO CString

foreign import ccall unsafe "f2e_parse_process"
  c_parse_process :: IO CString

foreign import ccall unsafe "f2e_parse_process_from_file"
  c_parse_process_from_file :: CString -> IO CString

foreign import ccall unsafe "f2e_free"
  c_free :: CString -> IO ()

decodeOwned :: CString -> IO (Map Text Text)
decodeOwned ptr
  | ptr == nullPtr = pure Map.empty
  | otherwise = do
      raw <- peekCString ptr
      c_free ptr
      case eitherDecodeStrict' (BS.pack raw) of
        Right parsed -> pure parsed
        Left err -> fail err

withArgvJson :: [Text] -> (CString -> IO a) -> IO a
withArgvJson argv action =
  let raw = BS.unpack (BL.toStrict (encode argv)) in
  withCString raw action

parse :: [Text] -> IO (Map Text Text)
parse argv =
  withArgvJson argv (c_parse_json_argv >=> decodeOwned)

parseFromFile :: FilePath -> [Text] -> IO (Map Text Text)
parseFromFile configPath argv =
  withCString configPath $ \config ->
    withArgvJson argv $ \encoded ->
      c_parse_json_argv_from_file config encoded >>= decodeOwned

parseProcess :: IO (Map Text Text)
parseProcess =
  c_parse_process >>= decodeOwned

parseProcessFromFile :: FilePath -> IO (Map Text Text)
parseProcessFromFile configPath =
  withCString configPath (c_parse_process_from_file >=> decodeOwned)

apply :: Map Text Text -> [Text] -> IO (Map Text Text)
apply env argv = do
  parsed <- parse argv
  pure (Map.union parsed env)
