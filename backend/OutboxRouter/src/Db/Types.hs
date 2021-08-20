{-# LANGUAGE DataKinds            #-}
{-# LANGUAGE DeriveGeneric        #-}
{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE TypeFamilies         #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
module Db.Types
where

import           Data.Has                   (Has (hasLens))
import           Data.Pool
import           Database.PostgreSQL.Simple
import           RIO
import           System.Envy

type DBConnectionString = ByteString

type DbConnection = Pool Connection

class HasDbFunc env where
  dbFuncL :: Lens' env DbConnection

-- instance HasDbFunc DbConnection where
--   dbFuncL = id

instance {-# OVERLAPPABLE #-} Has DbConnection a => HasDbFunc a where
  dbFuncL = hasLens

data PgSettings = PgSettings
  { connectionString :: !DBConnectionString,
    poolStripe       :: !Int,
    poolStripeMax    :: !Int,
    poolIdleSeconds  :: !Int
  }
  deriving (Eq,Show,Generic)

instance FromEnv PgSettings where
  fromEnv = gFromEnvCustom Option { dropPrefixCount=0, customPrefix = "PG" }
