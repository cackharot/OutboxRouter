{-# LANGUAGE DeriveAnyClass  #-}
{-# LANGUAGE DeriveGeneric   #-}
{-# LANGUAGE TemplateHaskell #-}
module Types
  ( OutboxMessage (..),
    TokenData (..),
    TokenEntry (..),
  )
where

import           Data.Aeson.TH
import qualified Data.Binary                        as By
import qualified Data.ByteString.Lazy               as LB
import           Database.PostgreSQL.Simple         (Binary)
import           Database.PostgreSQL.Simple.FromRow
import           RIO

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
