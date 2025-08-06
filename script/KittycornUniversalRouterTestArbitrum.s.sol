// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import 'forge-std/console2.sol';
import {Script} from 'forge-std/Script.sol';
import 'forge-std/Test.sol';
import {RouterParameters} from 'contracts/types/RouterParameters.sol';
import {IAllowanceTransfer} from 'v4-periphery/lib/permit2/src/interfaces/IAllowanceTransfer.sol';
import {IV4Router} from 'v4-periphery/src/interfaces/IV4Router.sol';
import {Constants} from 'v4-core/test/utils/Constants.sol';
import {Currency, CurrencyLibrary} from 'v4-core/src/types/Currency.sol';
import {Plan, Planner} from 'v4-periphery/test/shared/Planner.sol';
import {Actions} from 'v4-periphery/src/libraries/Actions.sol';
import {UniversalRouter} from '../contracts/UniversalRouter.sol';
import {Commands} from '../contracts/libraries/Commands.sol';
import {KittycornBank} from '@kittycorn/src/core/KittycornBank.sol';
import {Tokenize} from '@kittycorn/src/tokenize/Tokenize.sol';
import {ERC20} from 'solmate/src/tokens/ERC20.sol';
import {SafeTransferLib} from 'solmate/src/utils/SafeTransferLib.sol';
import {RouterPlanner, CurrencyPath} from '@kittycorn/src/utils/RouterPlanner.sol';

contract KittycornUniversalRouterTest is RouterPlanner, Script, Test {
    using SafeTransferLib for *;

    address deployer;
    address usdt;
    address usdc;
    address weth;
    address wbtc;
    address aave;

    UniversalRouter universalRouter;
    KittycornBank bank;
    IAllowanceTransfer permit2;

    Tokenize tUsdt;
    Tokenize tUsdc;
    Tokenize tWeth;
    Tokenize tWbtc;
    Tokenize tAave;
    Tokenize tLink;

    function setUp() public {
        deployer = msg.sender;

        // Deploy Universal-router Arbitrum
        RouterParameters memory params = RouterParameters({
            permit2: 0x000000000022D473030F116dDEE9F6B43aC78BA3,
            weth9: 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1,
            v2Factory: 0xf1D7CC64Fb4452F05c498126312eBE29f30Fbcf9,
            v3Factory: 0x1F98431c8aD98523631AE4a59f267346ea31F984,
            pairInitCodeHash: 0x96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f,
            poolInitCodeHash: 0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54,
            v4PoolManager: 0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32,
            v3NFTPositionManager: 0xC36442b4a4522E871399CD717aBDD847Ab11FE88,
            v4PositionManager: 0x0989f4a52CC70099392b38e3D405e4F515D12630,
            kittycornBank: 0xf0E778F51865B9c3bCbfE2B59aD19A12d6d1a0Fc
        });
        universalRouter = new UniversalRouter(params);

        permit2 = IAllowanceTransfer(params.permit2);
        bank = KittycornBank(params.kittycornBank);

        usdt = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
        usdc = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
        weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
        wbtc = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
        aave = 0xba5DdD1f9d7F570dc94a51479a000E3BCE967196;

        tUsdt = Tokenize(0x93Ee5B16F4dDE4566b94488B8d929F39df112f60);
        tUsdc = Tokenize(0x43297FBD1306f9fcDf96EE3A27e0113E4295D738);
        tWeth = Tokenize(0xCfdAb139Da7252EC3D8Df14F03659A46d1d1848C);
        tWbtc = Tokenize(0x8fecD0452BBF493C4915834E75310a5e8fe1FdDe);
        tAave = Tokenize(0x3eD9D2e07d314f2DcA05f920Ed5cbF2DFF60bC9a);
        tLink = Tokenize(0xDd816723CF1B310d1755156c4f37b4c8ed54ED5C);

        vm.label(address(deployer), 'Deployer');
        vm.label(address(permit2), 'Permit2');
        vm.label(address(universalRouter), 'UniversalRouter');
        vm.label(address(bank), 'KittycornBank');
        vm.label(usdt, 'USDT');
        vm.label(usdc, 'USDC');
        vm.label(weth, 'WETH');
        vm.label(wbtc, 'WBTC');
        vm.label(aave, 'AAVE');
        vm.label(address(tUsdt), 'tUSDT');
        vm.label(address(tUsdc), 'tUSDC');
        vm.label(address(tWeth), 'tWETH');
        vm.label(address(tWbtc), 'tWBTC');

        // Set ETH balance for deployer
        vm.deal(deployer, 1_000 ether);

        // Set USDT, USDC balance for deployer
        deal(usdt, deployer, 1_000_000 * baseDecimals(usdt));
        deal(usdc, deployer, 1_000_000 * baseDecimals(usdc));

        // Set WETH balance for deployer
        deal(weth, deployer, 2_000 * baseDecimals(weth));

        console2.log('\n== Initial balance ==');
        console2.log('Initial ETH balance:', deployer.balance / 1 ether);
        console2.log('Initial USDT balance:', ERC20(usdt).balanceOf(deployer) / baseDecimals(usdt));
        console2.log('Initial USDC balance:', ERC20(usdc).balanceOf(deployer) / baseDecimals(usdc));
        console2.log('Initial WETH balance:', ERC20(weth).balanceOf(deployer) / baseDecimals(weth));
        console2.log('Initial WBTC balance:', ERC20(wbtc).balanceOf(deployer) / baseDecimals(wbtc));
    }

    function run() public {
        vm.startPrank(deployer);

        // UniversalRouter swap with permit
        {
            safeApprove(weth, address(permit2), type(uint256).max);

            CurrencyPath[] memory path = new CurrencyPath[](4);
            path[0] = currencyPath(Currency.wrap(address(tWeth)), 500);
            path[1] = currencyPath(Currency.wrap(address(tUsdc)), 100);
            path[2] = currencyPath(Currency.wrap(address(tUsdt)), 500);
            path[3] = currencyPath(Currency.wrap(address(tWbtc)));
            uint256 amountIn = (1 * baseDecimals(address(tWeth))) / 100; // 0.01 weth
            universalRouterSwapExactInput(path, amountIn, deployer);
        }

        // UniversalRouter swap native
        {
            CurrencyPath[] memory path = new CurrencyPath[](6);
            path[0] = currencyPath(CurrencyLibrary.ADDRESS_ZERO);
            path[1] = currencyPath(Currency.wrap(address(weth)));
            path[2] = currencyPath(Currency.wrap(address(tWeth)), 500);
            path[3] = currencyPath(Currency.wrap(address(tUsdc)), 100);
            path[4] = currencyPath(Currency.wrap(address(tUsdt)), 500);
            path[5] = currencyPath(Currency.wrap(address(tWbtc)));

            uint256 amountIn = (5 * baseDecimals(address(weth))) / 10000; // 0.0005 ETH
            universalRouterSwapNativeExactInput(path, amountIn, deployer);
        }

        {
            safeApprove(weth, address(permit2), type(uint256).max);

            CurrencyPath[] memory path = new CurrencyPath[](5);
            path[0] = currencyPath(Currency.wrap(address(weth)), 500);
            path[1] = currencyPath(Currency.wrap(address(usdc)), 3000);
            path[2] = currencyPath(Currency.wrap(address(aave)));
            path[3] = currencyPath(Currency.wrap(address(tAave)), 3000);
            path[4] = currencyPath(Currency.wrap(address(tLink)));

            uint256 amountIn = (2 * baseDecimals(address(weth))) / 10000; // 0.0002 WETH
            universalRouterSwapExactInput(path, amountIn, deployer);
        }

        vm.stopPrank();

        console2.log('\n== Post balance ==');
        console2.log('USDT balance:', ERC20(usdt).balanceOf(deployer) / baseDecimals(usdt));
        console2.log('USDC balance:', ERC20(usdc).balanceOf(deployer) / baseDecimals(usdc));
        console2.log('WETH balance:', ERC20(weth).balanceOf(deployer) / baseDecimals(weth));
        console2.log('WBTC balance:', ERC20(wbtc).balanceOf(deployer) / baseDecimals(wbtc));
    }

    function universalRouterSwapNativeExactInput(
        CurrencyPath[] memory _path,
        uint256 _amountIn,
        address _takeRecipient
    ) public {
        // Check Reduce path and get tokenIn, tokenOut
        (CurrencyPath[] memory path, address tokenIn, address tokenOut) = getReducePath(bank, _path);

        // Get Exact Input Params
        IV4Router.ExactInputParams memory params = getExactInputParams(path, _amountIn);

        // Get Planner for path
        Plan memory planner = Planner.init();
        planner = planner.add(Actions.SWAP_EXACT_IN, abi.encode(params));
        planner = getPlannerForPath(bank, planner, path, _takeRecipient);
        bytes memory data = planner.encode();

        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.V4_SWAP)));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = data;

        uint256 beforeBalanceOut = path[path.length - 1].currency.isAddressZero()
            ? _takeRecipient.balance
            : ERC20(tokenOut).balanceOf(_takeRecipient);

        uint256 value = path[0].currency.isAddressZero() ? _amountIn : 0;
        universalRouter.execute{value: value}(commands, inputs);

        uint256 afterBalanceOut = path[path.length - 1].currency.isAddressZero()
            ? _takeRecipient.balance
            : ERC20(tokenOut).balanceOf(_takeRecipient);

        console2.log('\n== UniversalRouter Swap Native Exact Input %d Hops ==', (path.length - 1));
        console2.log('TokenIn:', tokenIn);
        console2.log('TokenOut:', tokenOut);
        console2.log('AmountIn:', _amountIn);
        console2.log('AmountOut:', (afterBalanceOut - beforeBalanceOut));
    }

    function universalRouterSwapExactInput(
        CurrencyPath[] memory _path,
        uint256 _amountIn,
        address _takeRecipient
    ) public {
        // Check Reduce path and get tokenIn, tokenOut
        (CurrencyPath[] memory path, address tokenIn, address tokenOut) = getReducePath(bank, _path);

        // Make permitBatch
        (, , uint48 nonce) = permit2.allowance(deployer, tokenIn, address(universalRouter));

        IAllowanceTransfer.PermitDetails[] memory permitDetails = new IAllowanceTransfer.PermitDetails[](1);
        permitDetails[0] = IAllowanceTransfer.PermitDetails(tokenIn, uint160(_amountIn), type(uint48).max, nonce);
        IAllowanceTransfer.PermitBatch memory permitBatch = IAllowanceTransfer.PermitBatch(
            permitDetails,
            address(universalRouter),
            block.timestamp + 100
        );

        // Sign the permitBatch
        bytes memory signature = signPermitBatchSignature(permitBatch, permit2.DOMAIN_SEPARATOR());

        // Get Exact Input Params
        IV4Router.ExactInputParams memory params = getExactInputParams(path, _amountIn);

        // Get Planner for path
        Plan memory planner = Planner.init();
        planner = planner.add(Actions.SWAP_EXACT_IN, abi.encode(params));
        planner = getPlannerForPath(bank, planner, path, _takeRecipient);
        bytes memory data = planner.encode();

        bytes memory commands = abi.encodePacked(
            bytes1(uint8(Commands.PERMIT2_PERMIT_BATCH)),
            bytes1(uint8(Commands.V4_SWAP))
        );
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(permitBatch, signature);
        inputs[1] = data;

        uint256 beforeBalance = ERC20(tokenOut).balanceOf(_takeRecipient);

        universalRouter.execute(commands, inputs);

        uint256 afterBalance = ERC20(tokenOut).balanceOf(_takeRecipient);

        console2.log('\n== UniversalRouter Swap Exact Input %d Hops ==', (path.length - 1));
        console2.log('TokenIn:', tokenIn);
        console2.log('TokenOut:', tokenOut);
        console2.log('AmountIn:', _amountIn);
        console2.log('AmountOut:', (afterBalance - beforeBalance));
    }

    function signPermitBatchSignature(IAllowanceTransfer.PermitBatch memory permitBatch, bytes32 domainSeparator)
        public
        view
        returns (bytes memory)
    {
        bytes32 _PERMIT_DETAILS_TYPEHASH = keccak256(
            'PermitDetails(address token,uint160 amount,uint48 expiration,uint48 nonce)'
        );
        bytes32 _PERMIT_BATCH_TYPEHASH = keccak256(
            'PermitBatch(PermitDetails[] details,address spender,uint256 sigDeadline)PermitDetails(address token,uint160 amount,uint48 expiration,uint48 nonce)'
        );
        uint256 privateKey = vm.envUint('PRIVATE_KEY');

        bytes32[] memory permitHashes = new bytes32[](permitBatch.details.length);
        for (uint256 i = 0; i < permitBatch.details.length; ++i) {
            permitHashes[i] = keccak256(abi.encode(_PERMIT_DETAILS_TYPEHASH, permitBatch.details[i]));
        }
        bytes32 msgHash = keccak256(
            abi.encodePacked(
                '\x19\x01',
                domainSeparator,
                keccak256(
                    abi.encode(
                        _PERMIT_BATCH_TYPEHASH,
                        keccak256(abi.encodePacked(permitHashes)),
                        permitBatch.spender,
                        permitBatch.sigDeadline
                    )
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, msgHash);
        return bytes.concat(r, s, bytes1(v));
    }

    function safeApprove(
        address _token,
        address _spender,
        uint256 _amount
    ) public {
        address owner = deployer;
        if (ERC20(_token).allowance(owner, _spender) < _amount) {
            // Support non-standard ERC20 (USDT on Ethereum)
            // It's require to approve 0 before approve new amount
            // and check onlyPayloadSize(2 * 32)
            ERC20(_token).safeApprove(_spender, 0);
            ERC20(_token).safeApprove(_spender, _amount);
        } else if (_amount == 0) {
            // Revoke approval
            ERC20(_token).safeApprove(_spender, 0);
        }
    }

    function baseDecimals(address _token) public view returns (uint256) {
        return 10**ERC20(_token).decimals();
    }
}
