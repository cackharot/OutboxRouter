{-# LANGUAGE DeriveAnyClass  #-}
{-# LANGUAGE DeriveGeneric   #-}
{-# LANGUAGE TemplateHaskell #-}

module Types
  ( OutboxMessage (..),
    TokenData (..),
    TokenEntry (..),
  )
where

import           Data.Aeson
import qualified Data.Binary                        as By
import qualified Data.ByteString.Base64.Lazy        as B64
import qualified Data.Text.Lazy.Encoding            as TE
import           Database.PostgreSQL.Simple         (Binary (..))
import           Database.PostgreSQL.Simple.FromRow
import           RIO
import qualified RIO.ByteString.Lazy                as LB
import qualified RIO.Text.Lazy                      as TL

data OutboxMessage = OutboxMessage
  { _global_index     :: Int64,
    _type             :: String,
    _event_identifier :: String,
    _payload_type     :: String,
    _payload          :: Maybe (Binary LB.ByteString),
    _metadata         :: Maybe (Binary LB.ByteString),
    _timestamp        :: String
  }
  deriving (Eq, Show)

instance ToJSON OutboxMessage where
  toJSON (OutboxMessage i tpe ei pt p m tsp) =
    object
      [ "global_index" .= i,
        "type" .= tpe,
        "event_identifier" .= ei,
        "payload_type" .= pt,
        "payload" .= enc p,
        "metadata" .= enc m,
        "timestamp" .= tsp
      ]
    where
      enc :: Maybe (Binary LB.ByteString) -> Maybe TL.Text
      enc Nothing           = Nothing
      enc (Just (Binary j)) = Just $ TE.decodeUtf8 $ B64.encode j

--  toEncoding (OutboxMessage i tpe ei pt p m tsp) =
--    pairs ("name" .= name <> "age" .= age)

instance FromRow OutboxMessage where
  fromRow = OutboxMessage <$> field <*> field <*> field <*> field <*> field <*> field <*> field

data TokenData = TokenData
  { _last_index     :: !Int64,
    _last_timestamp :: !String,
    _gaps           :: ![Int64]
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
