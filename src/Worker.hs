module Worker (workerLoop) where

import           Control.Concurrent         (threadDelay)
import           Control.Monad
import           Data.Aeson
import qualified Data.Binary                as By
import qualified Data.ByteString.Lazy       as LB
import           Data.Maybe                 (fromJust)
import           Data.Pool
import           Database.PostgreSQL.Simple
import           Db.Types
import           Kafka.Producer.Types
import           KafkaPublisher
import           Prelude                    (head, last, print, putStr)
import           RIO                        hiding (async, cancel, threadDelay)
import           Types

readOutboxMessages pool index limit =
  withResource pool $ \conn -> do
    query
      conn
      "SELECT global_index,type,event_identifier,payload_type,payload,metadata,timestamp FROM outbox WHERE global_index > ? LIMIT ?"
      (index, limit) ::
      IO [OutboxMessage]

fetchTokenEntry :: Connection -> Int64 -> String -> IO (Maybe TokenEntry)
fetchTokenEntry conn segment processor_name = catch r handleErr
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
    handleErr e = do
      putStr "Error in fetching token entry record : "
      print (e :: SomeException)
      return Nothing

updateTokenData :: Connection -> TokenData -> Int64 -> String -> IO ()
updateTokenData conn tokenData segment processor_name = do
  -- putStrLn $ "Updating token entry token: " ++ (show tokenData)
  _ <-
    execute
      conn
      "UPDATE token_entry SET token=? WHERE segment=? AND processor_name=?"
      (d, segment, processor_name)
  return ()
  where
    d = Binary $ By.encode tokenData

withTokenEntryLock ::
  Pool Connection ->
  Int64 ->
  String ->
  (TokenEntry -> Connection -> IO ()) ->
  IO ()
withTokenEntryLock pool seg pn action =
  withResource pool $ \conn -> do
    withTransaction conn $ do
      te <- fetchTokenEntry conn seg pn
      when (isJust te) $ action (fromJust te) conn
      unless (isJust te) $ threadDelay 1000000

transformMessages :: [OutboxMessage] -> IO [(Maybe ByteString, Maybe ByteString)]
transformMessages = mapM tx
  where
    tx m = pure $ (getKey m, getPayload m)
    getKey x = Just $ fromString $ _type x
    getPayload x = jsonEnc $ _payload x
    jsonEnc Nothing           = Nothing
    jsonEnc (Just (Binary x)) = Just $ LB.toStrict $ encode $ jsonDecPayload x
    jsonDecPayload x = decode x :: Maybe Value

publishMessagesToTopic ::
  (Foldable t, MonadIO m) =>
  KafkaProducer ->
  t (Maybe ByteString, Maybe ByteString) ->
  m ()
publishMessagesToTopic publisher msgs = forM_ msgs send
  where
    send m = sendMessageSync publisher $ kpayload m
    kpayload m = uncurry (mkMessage "todo") m

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
        then return $ Just $ last msgs
        else return Nothing

workerLoop :: Pool Connection -> KafkaProducer -> IO b
workerLoop pool publisher = forever $ do
  withTokenEntryLock pool seg pn $ \te tconn -> do
    last_msg <- processMessages pool publisher (current_index te) 1000
    when (isJust last_msg) $ updateTokenData tconn (d $ fromJust last_msg) seg pn
    threadDelay 10000
    return ()
  where
    seg = 1
    pn = "process-1"
    current_index t = fromMaybe 1 (getTokenData $ _token t)
    getTokenData Nothing           = Nothing
    getTokenData (Just (Binary a)) = Just $ By.decode a
    d (OutboxMessage i _ _ _ _ _ t) = TokenData i t []
