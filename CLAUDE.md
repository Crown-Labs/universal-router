# Universal Router

Solidity fork of Uniswap Universal Router with the Kittycorn command extension. Maintained Kittycorn deployment: Base Sepolia only. See README.md for upstream revision, architecture, validation limits, and deployment steps.

Use Node.js 22+ and Foundry 1.4.4. Install Solidity package sources with `npm ci --ignore-scripts`, initialize submodules, then run `make build`, `make test`, and `npm audit`. npm does not publish this private repository. Foundry is the only maintained build/test toolchain.

Keep upstream contracts and Foundry tests. The old Hardhat integration/gas harness and multi-chain deploy scripts were intentionally removed; do not restore them automatically on upstream sync. Kittycorn end-to-end execution is tested by the sibling smart-order-router repository on a dedicated local Base Sepolia fork.

Deployment lives in script/kittycorn. `make deploy` simulates by default. Public broadcasting requires explicit authorization and a Foundry keystore. Do not read private keys from .env. Preserve unrelated user changes.
