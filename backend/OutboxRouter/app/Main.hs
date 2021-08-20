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
import qualified Data.Binary                        as By
import qualified Data.ByteString.Lazy               as LB
import           Data.Maybe                         (fromJust)
import           Data.Pool
import qualified Data.Text                          as T
import           Database.PostgreSQL.Simple
import           Database.PostgreSQL.Simple.FromRow
import           Db.Connection
import           Db.Migration
import           Db.Types
import           Options.Applicative.Simple
import qualified Paths_OutboxRouter
import           Prelude                            (head, last, print,
                                                     putStrLn)
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

data TokenData = TokenData
  { _last_index     :: !Int,
    _last_timestamp :: !String,
    _gaps           :: ![Int]
  }
  deriving (Generic, Show, Eq, By.Binary)

data TokenEntry = TokenEntry
  { _processor_name :: String,
    _segment        :: Int,
    _token_type     :: String,
    _token          :: Maybe (Binary LB.ByteString),
    _owner          :: String,
    _te_timestamp   :: String
  }
  deriving (Eq, Show)

instance FromRow TokenEntry where
  fromRow = TokenEntry <$> field <*> field <*> field <*> field <*> field <*> field

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
      "SELECT global_index,type,event_identifier,payload_type,timestamp FROM outbox WHERE global_index > ? LIMIT ?"
      (index, limit) ::
      IO [OutboxMessage]

fetchTokenEntry :: Connection -> Int64 -> String -> IO (Maybe TokenEntry)
fetchTokenEntry conn segment processor_name = catch r handle
  where
    r = do
      te <-
        query
          conn
          "SELECT processor_name,segment,token_type,token,owner,timestamp FROM token_entry WHERE segment=? AND processor_name=? FOR UPDATE NOWAIT"
          (segment, processor_name) ::
          IO [TokenEntry]
      if length te == 1
        then return $ Just $ head te
        else return Nothing
    handle e = do
      putStrLn $ show (e :: SomeException)
      return Nothing

updateTokenData :: Connection -> TokenData -> Int64 -> String -> IO ()
updateTokenData conn tokenData segment processor_name = do
  -- putStrLn $ "Updating token entry token: " ++ (show tokenData)
  execute
    conn
    "UPDATE token_entry SET token=? WHERE segment=? AND processor_name=?"
    (d, segment, processor_name)
  return ()
  where
    d = Binary $ By.encode tokenData

withTokenEntryLock pool seg pn action =
  withResource pool $ \conn -> do
    withTransaction conn $ do
      te <- fetchTokenEntry conn seg pn
      when (isJust te) $ action (fromJust te) conn
      unless (isJust te) $ threadDelay 1000000

transformMessages = return

publishMessagesToTopic = print

processMessages :: DbConnection -> Int64 -> Int64 -> IO (Maybe OutboxMessage)
processMessages pool index limit = do
  -- putStrLn $ "Reading outbox messages from index: " ++ show index ++ " with limit: " ++ show limit
  msgs <- readOutboxMessages pool index limit
  if null msgs
    then return Nothing
    else do
      tms <- transformMessages msgs
      _ <- publishMessagesToTopic tms
      if not (null tms)
        then return $ Just $ last tms
        else return Nothing

publisherLoop pool = forever $ do
  withTokenEntryLock pool seg pn $ \te tconn -> do
    last_msg <- processMessages pool (current_index te) 100
    when (isJust last_msg) $ updateTokenData tconn (d $ fromJust last_msg) seg pn
    threadDelay 100000
    return ()
  where
    seg = 1
    pn = "process-1"
    current_index t = fromMaybe 1 (getTokenData $ _token t)
    getTokenData Nothing           = Nothing
    getTokenData (Just (Binary a)) = Just $ By.decode a
    d (OutboxMessage i _ _ _ t) = TokenData i t []

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
