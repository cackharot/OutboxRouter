{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Main (main) where

import           Chakra
import           Configuration.Dotenv          (Config (..), defaultConfig,
                                                loadFile)
import           Control.Concurrent.ParallelIO
import           Control.Monad
import           Data.Aeson
import qualified Data.ByteString.Lazy          as LB
import           Data.Pool
import           Data.Time
import           Data.UUID
import           Data.UUID.V4
import           Database.PostgreSQL.Simple
import           DateTimeUtil
import           Db.Connection
import           Prelude                       (print, putStrLn)
import           RIO

work :: Pool Connection -> Int -> IO ()
work pool num = withResource pool $ \conn -> do
  rows <- genRows [1 .. num]
  cnt <- executeMany conn "INSERT INTO outbox (type,event_identifier,payload_type,payload,timestamp) VALUES (?,?,?,?,?)" rows
  print $ "Inserted " ++ show cnt ++ "records..."
  return ()
  where
    genRows = mapM gen
    gen i = do
      ei <- nextRandom
      now <- getCurrentTime
      let tsp = formatISO8601Nanos now in
        return (("TestType", toString ei, "JSON", mkPayload i tsp, tsp) :: (String, String, String, Binary ByteString, String))
    mkPayload i t = Binary $ LB.toStrict $ encode (jp i t)
    jp i t = (decode $ RIO.fromString ("{\"num\":" ++ show i ++ ", \"timestamp\": \"" ++ t ++ "\" }")) :: Maybe Value

main :: IO ()
main = do
  hSetBuffering stdin LineBuffering
  _ <- loadFile defaultConfig {configPath = [".env", ".env.secrets"]} -- load .env & .env.secrets file if available
  withAppSettingsFromEnv $ \pgSettings -> do
    putStrLn "Connecting to db"
    pool <- initConnectionPool pgSettings
    putStrLn "Inserting 200K records parallelly"
    parallel_ (replicate 4 (work pool 50000))
    stopGlobalPool
    return ()
  where
    handleErr e = do
      print (e :: SomeException)
      return ()
