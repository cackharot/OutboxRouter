STACK=stack
DC=docker-compose
CWD=$(shell pwd)
APP_NAME=OutboxRouter-exe
APP_PATH=$(shell stack exec which $(APP_NAME))
APP_BIN=$(subst $(CWD)/,,$(APP_PATH))
BIN="$(CWD)/bin"

build: # Build binaries
	$(STACK) build --local-bin-path $(BIN) --copy-bins
	# @echo "Binary file at $(APP_BIN)"
	# @BINARY_PATH=${APP_BIN} $(DC) build

test: # Run tests
	$(STACK) test

run: # Run app & support infra in a docker compose
	@docker-compose up -d

run-local: # Run app local without any support infra
	$(STACK) exec $(APP_NAME) -- --port 18080 +RTS -T -N2 -RTS
	#$(BIN)/todo-bff-exe --port 8443 --protocol http+tls --tlskey certs/localhost.key --tlscert certs/localhost.crt +RTS -T -N2 -RTS

.PHONY: clean test

clean: # clean workspace
	$(STACK) clean
	rm -rf $(BIN)/*
