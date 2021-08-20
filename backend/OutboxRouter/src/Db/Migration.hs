module Db.Migration
where

import           Database.PostgreSQL.Simple
import           Db.Types
import           RIO
import           Network.HostName
import           Control.Monad

initDB :: PgSettings -> IO ()
initDB pgSettings = let connStr = connectionString pgSettings in 
  bracket (connectPostgreSQL connStr) close $ \conn -> do
    _ <- execute_ conn "CREATE TABLE IF NOT EXISTS todo (id int PRIMARY KEY not null, title text not null, description text null);"
    setupTokenEntry conn
    return ()

setupTokenEntry conn = do
  [Only r] <- liftIO $ query_ conn "SELECT COUNT(*) FROM token_entry;" :: IO [Only Int]
  owner <- getHostName
  _ <- when (r == 0) $ do
    executeMany
      conn
      "INSERT INTO token_entry (processor_name,segment,token_type,owner,timestamp) VALUES (?,?,?,?,?);"
      [("process-1", 1, "Seq", owner, "2021-08-16T00:34:22Z") :: (String,Int,String,String,String)]
    return ()
  return ()
