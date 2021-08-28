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
import           Kafka.Consumer.Types
import           Kafka.Producer.Types
import           Kafka.Types
import           KafkaPublisher
import           Prelude                    (head, last, print, putStr)
import           RIO                        hiding (async, cancel, threadDelay)
import           Types

selectOutboxQuery :: Query
selectOutboxQuery =
  "SELECT global_index,type,event_identifier,payload_type,payload,metadata,timestamp FROM outbox WHERE global_index > ? LIMIT ?"

selectTokenEntryQuery :: Query
selectTokenEntryQuery =
  "SELECT processor_name,segment,token_type,token,owner,timestamp FROM token_entry WHERE segment=? AND processor_name=? FOR UPDATE NOWAIT"

readOutboxMessages' :: DbConnection -> a -> (a -> OutboxMessage -> IO a) -> Int64 -> Int64 -> IO a
readOutboxMessages' pool initState resAction index limit =
  withResource pool $ \conn ->
    foldWithOptions queryOpts conn selectOutboxQuery (index, limit) initState resAction
  where
    queryOpts = defaultFoldOptions {fetchQuantity = Fixed fq}
    fq = if limit >= 1000 then div il 2 else il
    il = fromIntegral limit

readOutboxMessages pool index limit =
  withResource pool $ \conn -> do
    query
      conn
      selectOutboxQuery
      (index, limit) ::
      IO [OutboxMessage]

fetchTokenEntry :: Connection -> Int64 -> String -> IO (Maybe TokenEntry)
fetchTokenEntry conn segment processor_name = catch r handleErr
  where
    r = do
      te <-
        query
          conn
          selectTokenEntryQuery
          (segment, processor_name) ::
          IO [TokenEntry]
      if length te == 1
        then return $ Just $ head te
        else return Nothing
    handleErr e = do
      putStr "Error in fetching token entry record : "
      print (e :: SomeException)
      return Nothing

updateTokenData :: Connection -> TokenData -> Int64 -> String -> IO Int64
updateTokenData conn tokenData segment processor_name =
  execute
    conn
    "UPDATE token_entry SET token=? WHERE segment=? AND processor_name=?"
    (d, segment, processor_name)
  where
    d = Binary $ By.encode tokenData

withTokenEntryLock ::
  Pool Connection ->
  Int64 ->
  String ->
  (TokenEntry -> Connection -> IO ()) ->
  IO ()
withTokenEntryLock pool seg pn action =
  withResource pool $ \conn ->
    withTransaction conn $ do
      te <- fetchTokenEntry conn seg pn
      when (isJust te) $ action (fromJust te) conn
      unless (isJust te) $ threadDelay 2000000 -- 200ms

transformMessages :: [OutboxMessage] -> IO [(Maybe ByteString, Maybe ByteString)]
transformMessages = mapM transformMessage

transformMessage :: OutboxMessage -> IO (Maybe ByteString, Maybe ByteString)
transformMessage m = pure (getKey m, getPayload m)
  where
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
publishMessagesToTopic publisher msgs = forM_ msgs (publishMessage publisher)

publishMessage ::
  MonadIO m =>
  KafkaProducer ->
  (Maybe ByteString, Maybe ByteString) ->
  m
    ( Either
        KafkaError
        Offset
    )
publishMessage publisher msg = sendMessageSync publisher $ uncurry (mkMessage "todo") msg

publishMessage' ::
  MonadIO m =>
  KafkaProducer ->
  (Maybe ByteString, Maybe ByteString) ->
  m
    ( Either
        KafkaError
        Offset
    )
publishMessage' publisher msg = sendMessage publisher $ uncurry (mkMessage "todo") msg

processMessages' :: DbConnection -> KafkaProducer -> Int64 -> Int64 -> IO (Maybe OutboxMessage)
processMessages' pool publisher = readOutboxMessages' pool Nothing tx
  where
    tx _ row = do
      tms <- transformMessage row
      _ <- publishMessage' publisher tms
      return $ Just row

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

workerLoop :: Int64 -> Pool Connection -> KafkaProducer -> IO b
workerLoop sizePerBatch pool publisher = do
  currTrackinIndex <- newEmptyMVar
  putMVar currTrackinIndex 0
  forever $ do
    withTokenEntryLock pool seg pn $ \te tconn -> do
      v <- takeMVar currTrackinIndex
      when (v /= current_index te) $ do
        putStr $ "\nStarting from index " ++ show (current_index te)
      putMVar currTrackinIndex (current_index te)
      last_msg <- processMessages' pool publisher (current_index te) sizePerBatch
      when (isJust last_msg) $ do
        _ <- updateTokenData tconn (d $ fromJust last_msg) seg pn
        putStr $ "\nUpdated token entry to index " ++ show (_global_index $ fromJust last_msg)
      threadDelay 100000 -- 100ms
      return ()
  where
    seg = 1
    pn = "process-1"
    current_index :: TokenEntry -> Int64
    current_index t = _last_index $ tdataFromBin (_token t)
    tdataFromBin t = fromMaybe (TokenData 1 "" []) (getTokenData t)
    getTokenData Nothing           = Nothing
    getTokenData (Just (Binary a)) = Just $ By.decode a
    d (OutboxMessage i _ _ _ _ _ t) = TokenData i t []
