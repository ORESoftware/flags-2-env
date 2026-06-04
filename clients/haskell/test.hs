{-# LANGUAGE OverloadedStrings #-}

import qualified Data.Map.Strict as Map
import Flags2Env

main :: IO ()
main = do
  parsed <- parseFromFile "tests/fixtures/.cli-flags.toml" ["app", "--debug=t", "--port", "8181"]
  if Map.lookup "DEBUG" parsed /= Just "true" || Map.lookup "PORT" parsed /= Just "8181"
    then fail "unexpected parsed map"
    else pure ()
