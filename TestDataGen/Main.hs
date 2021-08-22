{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Main (main) where

import           Chakra
import           Configuration.Dotenv       (Config (..), defaultConfig,
                                             loadFile)
import           Control.Monad
import           Data.Aeson
import qualified Data.Binary                as By
import qualified Data.ByteString.Lazy       as LB
import           Data.Pool
import           Data.Time
import           Data.UUID
import           Data.UUID.V4
import           Database.PostgreSQL.Simple
import           Db.Connection
import           Prelude                    (print, putStrLn)
import           RIO

work pool = withResource pool $ \conn -> do
  rows <- genRows [1 .. 1000]
  cnt <- executeMany conn "INSERT INTO outbox (type,event_identifier,payload_type,payload,timestamp) VALUES (?,?,?,?,?)" rows
  print $ "Inserted " ++ show cnt ++ "records..."
  return ()
  where
    genRows = mapM gen
    gen i = do
      ei <- nextRandom
      now <- getCurrentTime
      return (("TestType", toString ei, "JSON", mkPayload i, fmt now) :: (String, String, String, Binary ByteString, String))
    fmt = formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%S.%QZ" -- "%Y-%m-%dT%H:%M:%SZ"
    mkPayload i = Binary $ LB.toStrict $ encode (jp i)
    jp i = (decode $ RIO.fromString ("{\"num\":" ++ show i ++ "}")) :: Maybe Value

main :: IO ()
main = do
  hSetBuffering stdin LineBuffering
  _ <- loadFile defaultConfig {configPath = [".env", ".env.secrets"]} -- load .env & .env.secrets file if available
  withAppSettingsFromEnv $ \pgSettings -> do
    logFunc <- buildLogger "TestDataGen" "0.0.1"
    putStrLn "Connecting to db"
    pool <- initConnectionPool pgSettings
    putStrLn "Inserting records"
    catch (work pool) handleErr
    return ()
  where
    handleErr e = do
      putStrLn $ show (e :: SomeException)
      return ()
