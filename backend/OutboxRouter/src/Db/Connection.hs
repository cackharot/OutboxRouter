module Db.Connection
where

import RIO
import Data.Pool
import Database.PostgreSQL.Simple
import Db.Types

initConnectionPool :: PgSettings -> IO DbConnection
initConnectionPool pgSettings =
  let connStr = connectionString pgSettings
      stripes = poolStripe pgSettings
      stripesMax = poolStripeMax pgSettings
      idle = poolIdleSeconds pgSettings
  in
  createPool
    (connectPostgreSQL connStr)
    close
    stripes -- stripes
    (realToFrac idle) -- unused connections are kept open for a minute
    stripesMax -- max. 10 connections open per stripe
