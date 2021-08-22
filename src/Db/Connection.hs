module Db.Connection
  ( setupDb,
    initConnectionPool,
  )
where

import           Data.Pool
import           Database.PostgreSQL.Simple
import           Db.Migration
import           Db.Types
import           RIO

setupDb :: PgSettings -> IO DbConnection
setupDb pgSettings = do
  pool <- initConnectionPool pgSettings
  initDB pgSettings
  return pool

initConnectionPool :: PgSettings -> IO DbConnection
initConnectionPool pgSettings =
  let connStr = connectionString pgSettings
      stripes = poolStripe pgSettings
      stripesMax = poolStripeMax pgSettings
      idle = poolIdleSeconds pgSettings
   in createPool
        (connectPostgreSQL connStr)
        close
        stripes -- stripes
        (realToFrac idle) -- unused connections are kept open for a minute
        stripesMax -- max. 10 connections open per stripe
