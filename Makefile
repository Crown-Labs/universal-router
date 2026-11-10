.PHONY: build test deploy deploy-check
chain ?= base-sepolia
rpc ?= $(RPC_BASE_SEPOLIA_FORK_URL)
broadcast ?= false

build: ## Compile contracts
	forge build

test: ## Offline upstream and Kittycorn tests (fork suites require FORK_URL)
	forge test --no-match-contract '^(SwapProxyTest|V2DaiWeth|V2MockMock|V2MockWeth|V2WethApe)$$' --match-path 'test/foundry-tests/*.t.sol' -vv

deploy: ## Simulate; add broadcast=true wallet=<keystore> to deploy on Base Sepolia
	@test "$(chain)" = base-sepolia || { echo 'Only Kittycorn Base Sepolia is supported'; exit 1; }
	@test -n "$(rpc)" || { echo 'Set RPC_BASE_SEPOLIA_FORK_URL or rpc=<URL>'; exit 1; }
	@test "$(broadcast)" = false -o "$(broadcast)" = true || { echo 'broadcast must be true or false'; exit 1; }
	@if [ "$(broadcast)" = true ] && [ -z "$(wallet)" ]; then echo 'Use wallet=<Foundry keystore name> when broadcasting'; exit 1; fi
	@forge script script/kittycorn/Deploy.s.sol --rpc-url "$(rpc)" $(if $(sender),--sender "$(sender)") $(if $(wallet),--account "$(wallet)") $(if $(filter true,$(broadcast)),--broadcast,)

deploy-check: ## Read-only validation of router=<deployed address>
	@test "$(chain)" = base-sepolia || { echo 'Only Kittycorn Base Sepolia is supported'; exit 1; }
	@test -n "$(rpc)" -a -n "$(router)" || { echo 'Set rpc and router=<deployed address>'; exit 1; }
	@KITTYCORN_UNIVERSAL_ROUTER="$(router)" forge script script/kittycorn/DeployedCheck.s.sol --rpc-url "$(rpc)"
