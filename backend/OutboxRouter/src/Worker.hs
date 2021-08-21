module Worker (workerLoop) where

import           Control.Concurrent                 (threadDelay)
import           Control.Concurrent.Async
import           Control.Monad
import           Data.Aeson
import qualified Data.Binary                        as By
import qualified Data.ByteString.Lazy               as LB
import           Data.Maybe                         (fromJust)
import           Data.Pool
import qualified Data.Text                          as T
import           Database.PostgreSQL.Simple
import           Database.PostgreSQL.Simple.FromRow
import           Db.Types
import           Kafka.Producer.Types
import           KafkaPublisher
import           Options.Applicative.Simple
import           Prelude                            (head, last, print, putStr,
                                                     putStrLn)
import           RIO                                hiding (async, cancel,
                                                     threadDelay)
import           Types

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
      putStr "Error in fetching token entry record : "
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

publishMessagesToTopic publisher msgs = forM_ msgs send
  where
    send m = sendMessageSync publisher $ km m
    km m = mkMessage' "todo" (getKey m) (payload m)
    getKey x = fromString $ _type x
    payload x = LB.toStrict $ encode x

processMessages :: DbConnection -> KafkaProducer -> Int64 -> Int64 -> IO (Maybe OutboxMessage)
processMessages pool publisher index limit = do
  -- putStrLn $ "Reading outbox messages from index: " ++ show index ++ " with limit: " ++ show limit
  msgs <- readOutboxMessages pool index limit
  if null msgs
    then return Nothing
    else do
      tms <- transformMessages msgs
      _ <- publishMessagesToTopic publisher tms
      if not (null tms)
        then return $ Just $ last tms
        else return Nothing

workerLoop :: Pool Connection -> KafkaProducer -> IO b
workerLoop pool publisher = forever $ do
  withTokenEntryLock pool seg pn $ \te tconn -> do
    last_msg <- processMessages pool publisher (current_index te) 100
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
