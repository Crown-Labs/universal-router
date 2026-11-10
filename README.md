# Kittycorn Universal Router

Fork of [Uniswap Universal Router](https://github.com/Uniswap/universal-router), synchronized through `3be05ae`.
The Kittycorn integration supports **Base Sepolia only**. Upstream contract implementations and Foundry tests are retained. Old chain deployment scripts and the duplicate Hardhat/mainnet test harness are removed.

## Architecture

`contracts/KittycornUniversalRouter.sol` extends the upstream router with command `0x41`:

```solidity
abi.encode(address inputToken, uint256 maximumInput, bool payerIsUser, bytes actionPlan)
```

It funds a bounded input through Permit2, delegates the plan to the existing KittycornRouter, clears the allowance, and refunds unused input to the caller. The deployed KittycornRouter handles ERC4626 conversion and settlement. Standard `V4_SWAP` remains unchanged. The caller supplies the action plan's slippage limits and the Universal Router deadline. Use `buildKittycornUniversalMethodParameters` from our SDK instead of manually encoding it.

As with upstream V4 commands, a failed Kittycorn command reverts the execution; `ALLOW_REVERT` does not suppress it. Router balances are transient: `payerIsUser=false` spends funds already in the router and must be used within an atomic command sequence. Do not leave tokens in a permissionless router.

## Build and test

Use Node.js 22+ and Foundry 1.4.4. No private key is needed.

```sh
npm ci --ignore-scripts
git submodule update --init --recursive
make build
make test
npm audit
```

`make test` runs offline upstream and Kittycorn tests, including fuzzed funding/refunds, approval isolation, reentrancy, fee-on-transfer rejection, deadline rollback, and EIP-170 size. Five upstream mainnet fork suites require `FORK_URL` and are excluded from this offline target. They can be run separately with `forge test --isolate` and a mainnet RPC.

For the integration test with actual Permit2, Kittycorn Tokenize rates, and all three deployed Base Sepolia tokens, build the sibling SDK and SOR repositories, then run SOR's `npm run check:fork` on a local Base Sepolia Anvil fork. It restores its snapshots and never sends public transactions.

## Deploy on Base Sepolia

This deploys **only a new KittycornUniversalRouter**. Existing Bank, KittycornRouter, Tokenize contracts, Permit2, and pools are reused. There is no npm package to publish from this repository (`private: true`).

Set `RPC_BASE_SEPOLIA_FORK_URL` in your shell. Use a Foundry keystore named `deployer` for broadcasting; no script reads `.env` or `PRIVATE_KEY`.

Simulate first:

```sh
make deploy chain=base-sepolia sender=0xfff0BF131DAEa9bA4e97829D2d3043aaef3213ff
```

Broadcast only when ready:

```sh
make deploy chain=base-sepolia broadcast=true wallet=deployer
```

Use the printed address for a read-only check:

```sh
make deploy-check chain=base-sepolia router=<new-universal-router-address>
```

Pass that address as `universalRouter` to SOR/SDK, with a Unix `deadline`. Approve the underlying token to Permit2, then approve this router as the spender through Permit2. The SDK does not reuse old Kittycorn Universal Router addresses.

## Release order

1. Build/test/pack the six SDKs in `../sdks`.
2. Build/test SOR and run its local fork execution check.
3. Publish SDK packages, then the SOR npm package.
4. Deploy this contract and run the check above.
5. Configure the new router address in the consuming application.

Steps 3 and 4 are independent; both must be complete before an application uses the Permit2 integration. Direct KittycornRouter execution is already supported without deploying this wrapper.

## Maintenance scope

Use Foundry as the only Solidity build/test tool. The old Hardhat integration/gas-snapshot suite is no longer maintained here; it remains available at the upstream revision above. This is a deliberate reduction in historical test coverage, not proof that every upstream command is covered. Keep all Foundry tests and run the sibling SOR Base Sepolia execution matrix for Kittycorn changes. npm installs only the three Solidity source packages required by remappings; it is not a deployment/release tool for this repository.

When syncing upstream, review contract and Foundry-test changes independently from tooling/deployment changes. Do not restore removed chain deployment examples or Hardhat dependencies automatically.

## Compiler verification

Solidity 0.8.26 is retained for exact Uniswap dependency pragmas. Its version is in the affected range of the [Yul KnowledgeBase optimizer bug](https://www.soliditylang.org/blog/2026/10/22/solidity-0.8.38-release-announcement/). For this source snapshot, a differential compilation using the original compiler and the isolated fix backport produced identical creation/runtime bytecode for **46 nonempty contracts**, including KittycornUniversalRouter. The wrapper also matches the official-compiler Foundry artifact byte-for-byte and has a **24,193-byte** runtime (383 bytes below EIP-170).

[Evidence](audit/kittycorn-compiler-0.8.26.json) records all 116 source hashes, complete compiler settings, compiler binary hashes, and output hashes. The two native compiler binaries are the exact binaries validated by the eight positive controls in Crown-Labs/kittycorn-contracts `test/audit/compiler-0.8.26.json`. To reproduce, use the sources listed in the evidence, its Standard JSON settings, and those original/backported compilers; compare unmodified creation/runtime hex, including metadata, and the Foundry artifact. Local raw inputs/results are under `/tmp/kittycorn-ur-compiler-audit`. This proves equivalence only for that specific fix and the recorded sources/settings; repeat it after relevant changes.
