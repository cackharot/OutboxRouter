{-# LANGUAGE DataKinds         #-}
{-# LANGUAGE DeriveAnyClass    #-}
{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell   #-}
{-# LANGUAGE TypeOperators     #-}
{-# LANGUAGE UnicodeSyntax     #-}

module Main (main) where

import           Chakra
import           Configuration.Dotenv               (Config (..), defaultConfig,
                                                     loadFile)
import           Control.Concurrent                 (threadDelay)
import           Control.Concurrent.Async
import           Control.Monad
import           Data.Aeson.TH
import           Data.Pool
import qualified Data.Text                          as T
import           Database.PostgreSQL.Simple
import           Database.PostgreSQL.Simple.FromRow
import           Db.Connection
import           Db.Migration
import           Db.Types
import           Options.Applicative.Simple
import qualified Paths_OutboxRouter
import           Prelude                            (print)
import           RIO                                hiding (async, cancel,
                                                     threadDelay)
import           Servant

type HelloRoute = "hello" :> QueryParam "name" Text :> Get '[PlainText] Text

type API = HelloRoute :<|> EmptyAPI

type OutboxAppCtx = (ModLogger, InfoDetail, DbConnection)

type OutboxApp = RIO OutboxAppCtx

data OutboxMessage = OutboxMessage
  { _global_index     :: Int,
    _type             :: String,
    _event_identifier :: String,
    _payload_type     :: String,
    _timestamp        :: String
  }
  deriving (Eq, Show)

$(deriveJSON defaultOptions ''OutboxMessage)

instance FromRow OutboxMessage where
  fromRow = OutboxMessage <$> field <*> field <*> field <*> field <*> field

data TokenEntry = TokenEntry
  { _processor_name :: String,
    _segment        :: Int,
    _token_type     :: String,
    _owner          :: String,
    _te_timestamp   :: String
  }
  deriving (Eq, Show)

$(deriveJSON defaultOptions ''TokenEntry)

instance FromRow TokenEntry where
  fromRow = TokenEntry <$> field <*> field <*> field <*> field <*> field

hello :: Maybe Text -> BasicApp Text
hello name = do
  let name' = fromMaybe "Sensei!" name
  logInfo $ "Saying hello to " <> display name'
  return $ "Hello " <> name' <> "!"

setupDb pgSettings = do
  pool <- initConnectionPool pgSettings
  initDB pgSettings
  return pool

readOutboxMessages pool index limit =
  withResource pool $ \conn -> do
    query
      conn
      "SELECT global_index,type,event_identifier,payload_type,timestamp FROM outbox WHERE global_index = ? LIMIT ?"
      (index, limit) :: IO [OutboxMessage]

fetchTokenEntries conn =
  query_
    conn
    "SELECT processor_name,segment,token_type,owner,timestamp FROM token_entry WHERE segment =1 FOR UPDATE NOWAIT" ::
    IO [TokenEntry]

withTokenEntryLock pool action =
  withResource pool $ \conn -> do
    withTransaction conn $ do
      te <- fetchTokenEntries conn
      when (length te == 1) $ action te
      return ()

transformMessages = return

publishMessagesToTopic = print

publisherLoop pool = forever $ do
  withTokenEntryLock pool $ \_ -> do
    msgs <- readOutboxMessages pool (1 :: Int) (100 :: Int)
    tms <- transformMessages msgs
    _ <- publishMessagesToTopic tms
    threadDelay 3000000

main :: IO ()
main = do
  hSetBuffering stdin LineBuffering
  _ <- loadFile defaultConfig {configPath = [".env", ".env.secrets"]} -- load .env & .env.secrets file if available
  -- Load the  AppSettings data from ENV variables
  withAppSettingsFromEnv $ \appSettings ->
    withAppSettingsFromEnv $ \pgSettings -> do
      -- Override the version from cabal file
      let ver = $(simpleVersion Paths_OutboxRouter.version) -- TH to get cabal project's git sha version
          infoDetail = appSettings {appVersion = T.pack ver}
          appEnv = appEnvironment infoDetail
          appVer = appVersion infoDetail
          appAPI = Proxy :: Proxy API
          appServer = hello :<|> emptyServer
      logFunc <- buildLogger appEnv appVer
      middlewares <- chakraMiddlewares infoDetail
      pool <- setupDb pgSettings
      pl <- async $ publisherLoop pool
      runChakraAppWithMetrics
        middlewares
        EmptyContext
        (logFunc, infoDetail)
        appAPI
        appServer
      cancel pl
