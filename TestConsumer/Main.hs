{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Main (main) where

import           Chakra
import           Configuration.Dotenv (Config (..), defaultConfig, loadFile)
import           Db.Connection
import           Kafka.Consumer
import           Prelude              (print, putStrLn)
import           RIO

-- Global consumer properties
consumerProps :: ConsumerProperties
consumerProps =
  brokersList ["localhost:9092"]
    <> groupId "domain-1-consumer-grp"
    <> noAutoCommit
    <> setCallback (rebalanceCallback printingRebalanceCallback)
    <> setCallback (offsetCommitCallback printingOffsetCallback)
    <> logLevel KafkaLogInfo
    <> callbackPollMode CallbackPollModeSync

printingRebalanceCallback :: KafkaConsumer -> RebalanceEvent -> IO ()
printingRebalanceCallback _ e = case e of
  RebalanceBeforeAssign ps ->
    putStrLn $ "[Rebalance] About to assign partitions: " <> show ps
  RebalanceAssign ps ->
    putStrLn $ "[Rebalance] Assign partitions: " <> show ps
  RebalanceBeforeRevoke ps ->
    putStrLn $ "[Rebalance] About to revoke partitions: " <> show ps
  RebalanceRevoke ps ->
    putStrLn $ "[Rebalance] Revoke partitions: " <> show ps

hasError :: KafkaError -> Bool
hasError err = case err of
  KafkaResponseError RdKafkaRespErrNoError -> False
  _                                        -> True

printingOffsetCallback :: KafkaConsumer -> KafkaError -> [TopicPartition] -> IO ()
printingOffsetCallback _ e ps = unless (hasError e) $ do
  print ("Offsets callback:" ++ show e)
  mapM_ (print . (tpTopicName &&& tpPartition &&& tpOffset)) ps

-- Subscription to topics
consumerSub :: Subscription
consumerSub =
  topics ["domain-1-topic"]
    -- <> offsetReset Latest
    <> offsetReset Earliest

runmyConsumer :: IO ()
runmyConsumer = do
  -- print $ cpLogLevel consumerProps
  res <- bracket mkConsumer clConsumer runHandler
  print res
  where
    mkConsumer = newConsumer consumerProps consumerSub
    clConsumer (Left err) = return (Left err)
    clConsumer (Right kc) = maybe (Right ()) Left <$> closeConsumer kc
    runHandler (Left err) = return (Left err)
    runHandler (Right kc) = processMessages kc

processMessages :: KafkaConsumer -> IO (Either KafkaError ())
processMessages kfCmr = do
  -- replicateM_ 10 $ do
  forever $ do
    msg <- pollMessage kfCmr (Timeout 1_000)
    when (isRight msg) $ do
      putStrLn $ "Message: " <> show msg
    _ <- commitAllOffsets OffsetCommit kfCmr
    return ()
  return $ Right ()

main :: IO ()
main = do
  hSetBuffering stdin LineBuffering
  _ <- loadFile defaultConfig {configPath = [".env", ".env.secrets"]} -- load .env & .env.secrets file if available
  withAppSettingsFromEnv $ \pgSettings -> do
    runSimpleApp $ do
      logInfo "Connecting to db..."
      pool <- liftIO $ initConnectionPool pgSettings
      liftIO runmyConsumer
      logInfo "Done!"
      return ()
