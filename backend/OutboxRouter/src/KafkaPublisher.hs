{-# LANGUAGE OverloadedStrings #-}
module KafkaPublisher where

import qualified Data.Map       as M
import qualified Data.Text      as Text
import           Kafka.Producer
import           Prelude        (print)
import           RIO

-- Global producer properties
producerProps :: ProducerProperties
producerProps =
  brokersList ["192.168.1.15:9092"]
--    <> sendTimeout (Timeout 1000)
    <> extraProps (M.fromList [(Text.pack "broker.address.family", Text.pack "v4")])
    <> logLevel KafkaLogDebug

-- Topic to send messages to
targetTopic :: TopicName
targetTopic = "todo"

-- Run an example
runProducerExample :: IO ()
runProducerExample =
  bracket mkProducer clProducer runHandler >>= print
  where
    mkProducer = newProducer producerProps
    clProducer (Left _)     = return ()
    clProducer (Right prod) = closeProducer prod
    runHandler (Left err)   = return $ Left err
    runHandler (Right prod) = sendMessages prod

sendMessages :: KafkaProducer -> IO (Either KafkaError ())
sendMessages prod = do
  err1 <- produceMessage prod (mkMessage Nothing (Just "test from producer"))
  forM_ err1 print
  err2 <- produceMessage prod (mkMessage (Just "key") (Just "test from producer (with key)"))
  forM_ err2 print
  return $ Right ()

mkMessage :: Maybe ByteString -> Maybe ByteString -> ProducerRecord
mkMessage k v =
  ProducerRecord
    { prTopic = targetTopic,
      prPartition = UnassignedPartition,
      prKey = k,
      prValue = v
    }
