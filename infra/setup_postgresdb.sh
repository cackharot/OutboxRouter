#!/bin/bash -e

SRC="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

psql -h $DB_HOST -p $DB_PORT -U $DB_ADMIN_USER -a -f $SRC/db_init.sql

psql -h $DB_HOST -p $DB_PORT -U $DB_USER -a -f $SRC/db_tables.sql
