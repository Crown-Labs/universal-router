// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script} from 'forge-std/Script.sol';
import {console2} from 'forge-std/console2.sol';
import {KittycornUniversalRouter, IKittycornActionRouter} from 'contracts/KittycornUniversalRouter.sol';

/// @notice Read-only Base Sepolia deployment configuration check. Execution is covered by SOR's local fork check.
contract DeployedCheck is Script {
    /// @notice Verify code and integration target without transactions, keys or token approvals.
    function run() external view {
        require(block.chainid == 84532, 'BASE_SEPOLIA_REQUIRED');
        address deployed = vm.envAddress('KITTYCORN_UNIVERSAL_ROUTER');
        require(deployed.code.length != 0 && deployed.code.length <= 24576, 'INVALID_ROUTER_CODE');
        KittycornUniversalRouter router = KittycornUniversalRouter(payable(deployed));
        IKittycornActionRouter target = router.kittycornRouter();
        require(address(target) == 0x137a906E06EC20808c8F156F9024196427429220, 'KITTYCORN_ROUTER_MISMATCH');
        require(target.bank() == 0xcc331eC1d6CF4542F9eB988B49249cfa163081dc, 'BANK_MISMATCH');
        require(target.poolManager() == 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408, 'POOL_MANAGER_MISMATCH');
        require(router.KITTYCORN_SWAP() == 0x41, 'COMMAND_MISMATCH');
        console2.log('== Existing contracts ==');
        console2.log('KittycornUniversalRouter:', deployed);
        console2.log('KittycornRouter:', address(target));
        console2.log('KittycornBank:', target.bank());
        console2.log('PASS: Base Sepolia integration configuration');
    }
}
