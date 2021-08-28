{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE LambdaCase    #-}

module KafkaPublisher where

import qualified Data.Map             as M
import qualified Data.Text            as T
import           Kafka.Consumer.Types
import           Kafka.Producer
import           Prelude              (print)
import           RIO
import           System.Envy

data PublisherSettings = PublisherSettings
  { psBrokerList   :: !String,
    psClientId     :: !String,
    psTimeout      :: !Int64,
    psTopicName    :: !String,
    psSizePerBatch :: !Int64
  }
  deriving (Eq,Show,Generic)

instance FromEnv PublisherSettings where
  fromEnv = gFromEnvCustom Option { dropPrefixCount=2, customPrefix = "KAFKA" }

mkProducerProps :: PublisherSettings -> ProducerProperties
mkProducerProps s =
  brokersList [BrokerAddress $ T.pack $ psBrokerList s]
    <> extraProps
      ( M.fromList
          [ ("broker.address.family", "v4"),
            ("client.id", T.pack $ psClientId s)
          ]
      )
    <> logLevel KafkaLogInfo

withPublisher ::
  MonadIO m =>
  PublisherSettings ->
  (KafkaProducer -> IO (Either KafkaError b)) ->
  m (Either KafkaError b)
withPublisher props handler = liftIO $ do
  bracket mkProducer clProducer runHandler
  where
    mkProducer = newProducer $ mkProducerProps props
    clProducer (Left _)     = return ()
    clProducer (Right prod) = closeProducer prod
    runHandler (Left err)   = return $ Left err
    runHandler (Right prod) = handler prod

mkMessage' :: TopicName -> ByteString -> ByteString -> ProducerRecord
mkMessage' t k v = mkMessage t (Just k) (Just v)

mkMessage :: TopicName -> Maybe ByteString -> Maybe ByteString -> ProducerRecord
mkMessage t k v =
  ProducerRecord
    { prTopic = t,
      prPartition = UnassignedPartition,
      prKey = k,
      prValue = v
    }

sendMessage::
  MonadIO m =>
  KafkaProducer ->
  ProducerRecord ->
  m (Either KafkaError Offset)
sendMessage producer record = liftIO $ do
  err <- produceMessage producer record
  forM_ err print
  return  $ case err of
    Just e  -> Left e
    Nothing -> Right $ Offset 1

sendMessageSync ::
  MonadIO m =>
  KafkaProducer ->
  ProducerRecord ->
  m (Either KafkaError Offset)
sendMessageSync producer record = liftIO $ do
  var <- newEmptyMVar
  res <- produceMessage' producer record (putMVar var)
  case res of
    Left (ImmediateError err) -> pure (Left err)
    Right () -> do
      flushProducer producer
      takeMVar var
        >>= return . \x -> case x of
          DeliverySuccess _ offset -> Right offset
          DeliveryFailure _ err    -> Left err
          NoMessageError err       -> Left err
