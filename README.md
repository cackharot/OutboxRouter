# OutboxRouter

Implements the [Outbox Pattern](https://microservices.io/patterns/data/transactional-outbox.html) pattern that avoid the 2PC (Two Phase Commits) in distributed systems.

This app is opinionated and works with source (PostgreSQL) and sink (Kafka).
This app has high reliability - one can run multiple instances, but only one will be actively publishing, if the active one crashes other instance will take ownership and continue where it left off.

## Usage

* Run `stack build`
* Run `stack exec -- OutboxRouter-exe` to start the server


## Configuration

This follows 12 Factor app principles all configs are read from system environment variables.
Check out the `.env` file

## PostgreSQL Schema

This app requires two tables of the below schema
