STACK=stack
DC=docker-compose
CWD=$(shell pwd)
APP_NAME=OutboxRouter-exe
APP_PATH=$(shell stack exec which $(APP_NAME))
APP_BIN=$(subst $(CWD)/,,$(APP_PATH))
BIN="$(CWD)/bin"

watch: # Build binaries
	$(STACK) build --file-watch --fast --local-bin-path $(BIN) --copy-bins

watch-ghcid:
	 ghcid -v --command "stack ghci OutboxRouter:exe:OutboxRouter-exe --ghci-options=-fobject-code" --warnings

build: # Build binaries
	$(STACK) build --local-bin-path $(BIN) --copy-bins

docker-build:
	@echo "Binary file at $(APP_BIN)"
	@BINARY_PATH=${APP_BIN} $(DC) build

test: # Run tests
	$(STACK) test

run-watch: # run
	$(STACK) run --file-watch --fast

run: # Run app & support infra in a docker compose
	@docker-compose up -d

run-local2: # Run app local without any support infra
	$(STACK) exec $(APP_NAME) -- --port 18081 +RTS -T -N2 -RTS

run-local: # Run app local without any support infra
	$(STACK) exec $(APP_NAME) -- --port 18080 +RTS -T -N2 -sstderr -RTS

run-test-data-gen-local:
	$(STACK) exec TestDataGen-exe -- +RTS -T -N2 -sstderr -RTS

run-local-tls:
	$(APP_BIN)/$(APP_NAME) --port 8443 --protocol http+tls --tlskey certs/localhost.key --tlscert certs/localhost.crt +RTS -T -N2 -RTS

.PHONY: clean test

clean: # clean workspace
	$(STACK) clean
	rm -rf $(BIN)/*
