// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script} from 'forge-std/Script.sol';
import {console2} from 'forge-std/console2.sol';
import {KittycornUniversalRouter} from 'contracts/KittycornUniversalRouter.sol';
import {RouterParameters} from 'contracts/types/RouterParameters.sol';

/// @notice Deploy the current Kittycorn integration on Base Sepolia; forge simulates unless --broadcast is supplied.
contract DeployKittycorn is Script {
    /// @notice Use the existing Bank/Router and upstream dependencies; no private key is read by this script.
    /// @return router Newly deployed Universal Router with Kittycorn command 0x41.
    function run() external returns (KittycornUniversalRouter router) {
        require(block.chainid == 84532, 'BASE_SEPOLIA_REQUIRED');
        RouterParameters memory params = RouterParameters({
            permit2: 0x000000000022D473030F116dDEE9F6B43aC78BA3,
            weth9: 0x4200000000000000000000000000000000000006,
            v2Factory: 0x7Ae58f10f7849cA6F5fB71b7f45CB416c9204b1e,
            v3Factory: 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24,
            pairInitCodeHash: 0x96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f,
            poolInitCodeHash: 0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54,
            v4PoolManager: 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408,
            permissionsAdapterFactory: address(0),
            v3NFTPositionManager: 0x27F971cb582BF9E50F397e4d29a5C7A34f11faA2,
            v4PositionManager: 0x4B2C77d209D3405F41a037Ec6c77F7F5b8e2ca80,
            spokePool: address(0)
        });
        address actionRouter = 0x137a906E06EC20808c8F156F9024196427429220;
        vm.startBroadcast();
        router = new KittycornUniversalRouter(params, actionRouter);
        vm.stopBroadcast();
        console2.log('== Deploy contracts ==');
        console2.log('KittycornRouter:', actionRouter);
        console2.log('KittycornUniversalRouter:', address(router));
    }
}
