{-# LANGUAGE DataKinds       #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeOperators   #-}
{-# LANGUAGE UnicodeSyntax   #-}

module Main (main) where

import           Chakra
import           Configuration.Dotenv       (Config (..), defaultConfig,
                                             loadFile)
import           Control.Monad
import qualified Data.Text                  as T
import           Db.Connection
import           Db.Types
import           KafkaPublisher
import           Options.Applicative.Simple
import qualified Paths_OutboxRouter
import           RIO
import           Servant
import           Worker

type HelloRoute = "hello" :> QueryParam "name" Text :> Get '[PlainText] Text

type API = HelloRoute :<|> EmptyAPI

type OutboxAppCtx = (ModLogger, InfoDetail, DbConnection)

type OutboxApp = RIO OutboxAppCtx

hello :: Maybe Text -> OutboxApp Text
hello name = do
  let name' = fromMaybe "Sensei!" name
  logInfo $ "Saying hello to " <> display name'
  return $ "Hello " <> name' <> "!"

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
      pl <- async $
        withAppSettingsFromEnv $ \publisherSettings -> do
          _ <- withPublisher publisherSettings $ workerLoop publisherSettings pool
          return ()
      runChakraAppWithMetrics
        middlewares
        EmptyContext
        (logFunc, infoDetail, pool)
        appAPI
        appServer
      cancel pl
