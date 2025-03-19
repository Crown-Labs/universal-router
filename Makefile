.PHONY: test 
-include .env
FORK_BLOCK_FLAG = $(if $(RPC_FORK_BLOCK_NUMBER),--fork-block-number $(RPC_FORK_BLOCK_NUMBER),)

env:
	cp example.env .env

clean:
	forge clean

compile: 
	forge compile -vvvvv
	
build: 
	forge compile -vvvvv

anvil-start:
	anvil -m $(MNEMONIC) --fork-url $(RPC_FORK_URL) $(FORK_BLOCK_FLAG)

anvil-stop:
	pkill -f anvil

anvil-run: 
	forge script $(f) --sig 'run' --fork-url http://127.0.0.1:8545 --private-key $(PRIVATE_KEY) --broadcast $(p)

anvil-deploy: 
	forge script $(f) --sig 'run' --fork-url $(RPC_FORK_URL) --private-key $(PRIVATE_KEY) --broadcast $(p)

anvil-test: 
	for file in $$(find script -name "*Test.s.sol"); do \
		echo "\nRunning $$file..."; \
		forge script $$file --sig 'run' --fork-url http://127.0.0.1:8545 --private-key $(PRIVATE_KEY) --broadcast $(p) || exit 1; \
	done; \

test: 
	@if [ -z "$(f)" ]; then \
		forge test $(p); \
	else \
		forge test --match-path $(f) $(p); \
	fi
