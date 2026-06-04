{-# LANGUAGE OverloadedStrings #-}

import qualified Data.Map.Strict as Map
import Flags2Env

main :: IO ()
main = do
  let configPath = "flags2env-haskell-smoke.toml"
  writeFile configPath $ unlines
    [ "[flags.port]"
    , "env = \"PORT\""
    , "aliases = [\"port\"]"
    , "type = \"integer\""
    , ""
    , "[flags.debug]"
    , "env = \"DEBUG\""
    , "aliases = [\"debug\"]"
    , "type = \"bool\""
    , "true_aliases = [\"t\"]"
    ]
  parsed <- parseFromFile configPath ["app", "--debug=t", "--port", "8181"]
  if Map.lookup "DEBUG" parsed /= Just "true" || Map.lookup "PORT" parsed /= Just "8181"
    then fail "unexpected parsed map"
    else pure ()
