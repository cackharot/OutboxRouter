# Infra setup snippets

* Haskell
* PostgreSQL


## Git ignore

``` sh
curl -s -o .gitignore "https://www.toptal.com/developers/gitignore/api/haskell,macos,windows,linux,visualstudiocode,emacs,vim"
```

## PostgreSQL

Create `~/.pgpass` file and store the password for `postgres` db user to create and initalize app database & users.

``` sh
./infra/setup_postgresdb.sh
```

