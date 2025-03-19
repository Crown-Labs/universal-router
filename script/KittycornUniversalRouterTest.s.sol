// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import 'forge-std/console2.sol';
import {Script} from 'forge-std/Script.sol';
import 'forge-std/Test.sol';
import {IV4Router} from 'v4-periphery/src/interfaces/IV4Router.sol';
import {IHooks} from 'v4-core/src/interfaces/IHooks.sol';
import {PathKey} from 'v4-periphery/src/libraries/PathKey.sol';
import {PoolKey} from 'v4-core/src/types/PoolKey.sol';
import {Constants} from 'v4-core/test/utils/Constants.sol';
import {Currency} from 'v4-core/src/types/Currency.sol';
import {Plan, Planner} from 'v4-periphery/test/shared/Planner.sol';
import {Actions} from 'v4-periphery/src/libraries/Actions.sol';
import {ActionConstants} from 'v4-periphery/src/libraries/ActionConstants.sol';
import {UniversalRouter} from '../contracts/UniversalRouter.sol';
import {Commands} from '../contracts/libraries/Commands.sol';
import {KittycornBank} from '@kittycorn/src/core/KittycornBank.sol';
// import {KittycornPositionManager} from '../../src/KittycornPositionManager.sol';
import {KittycornRouter} from '@kittycorn/src/KittycornRouter.sol';
import {Tokenize} from '@kittycorn/src/tokenize/Tokenize.sol';
import {ERC20} from 'solmate/src/tokens/ERC20.sol';
import {SafeTransferLib} from 'solmate/src/utils/SafeTransferLib.sol';

// import {ERC721} from 'solmate/src/tokens/ERC721.sol';
// import {MockKittycornBankLiquidator} from '../../test/mocks/MockKittycornBankLiquidator.sol';
// import {KittycornScriptBase} from '../utils/KittycornScriptBase.sol';
// import {AddressConfig} from '../shared/ConfigBase.sol';

contract KittycornUniversalRouterTest is Script, Test {
    using SafeTransferLib for *;

    Tokenize tUsdt;
    Tokenize tUsdc;
    // Tokenize tWeth;

    // address weth;
    address eth = address(0x0);
    address usdt = 0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0;
    address usdc = 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8;

    address deployer;

    UniversalRouter universalRouter;
    KittycornRouter router;
    KittycornBank bank;

    function setUp() public {
        deployer = msg.sender;

        universalRouter = UniversalRouter(payable(0x7B1994Bd03016e48b82BbB726D555605B80bC8c0));
        router = KittycornRouter(payable(0x561A87303005D9C83FbD94dDEb80D63528fCD448));
        bank = KittycornBank(address(router.bank()));

        tUsdt = Tokenize(0x137a906E06EC20808c8F156F9024196427429220);
        tUsdc = Tokenize(0x1E271DB8D8B446A0DEe8e9D774f4213e9Bc1C6ba);

        // vm.label(address(router), 'UniversalRouter');
        vm.label(address(router), 'KittycornRouter');
        // vm.label(weth, 'WETH');
        vm.label(usdt, 'USDT');
        vm.label(usdc, 'USDC');
        vm.label(address(tUsdt), 'tUSDT');
        vm.label(address(tUsdc), 'tUSDC');

        // Set ETH balance for deployer
        vm.deal(deployer, 1_000 ether);

        // Set USDT, USDC balance for deployer
        deal(usdt, deployer, 1_000_000 * baseDecimals(usdt));
        deal(usdc, deployer, 1_000_000 * baseDecimals(usdc));

        // Set WETH balance for deployer
        // deal(weth, deployer, 2_000 * baseDecimals(weth));

        console2.log('\n== Initial balance ==');
        console2.log('Initial ETH balance:', deployer.balance / 1 ether);
        console2.log('Initial USDT balance:', ERC20(usdt).balanceOf(deployer) / baseDecimals(usdt));
        console2.log('Initial USDC balance:', ERC20(usdc).balanceOf(deployer) / baseDecimals(usdc));
        // console2.log('Initial WETH balance:', ERC20(weth).balanceOf(deployer) / baseDecimals(weth));
    }

    function run() public {
        // vm.startBroadcast();

        // safeApprove(usdc, address(universalRouter), type(uint256).max);
        // safeApprove(usdt, address(universalRouter), type(uint256).max);

        // vm.stopBroadcast();
        // return;

        vm.startPrank(deployer);

        // Using UniversalRouter
        {
            Currency[] memory path = new Currency[](2);
            path[0] = Currency.wrap(address(tUsdc));
            path[1] = Currency.wrap(address(tUsdt));
            uint256 amountIn = 2000 * baseDecimals(address(tUsdc));
            // safeApprove(usdc, address(universalRouter), amountIn);
            universalRouterSwapExactInput(path, amountIn, deployer);
        }

        // Using KittycornRouter
        {
            // Currency[] memory path = new Currency[](2);
            // path[0] = Currency.wrap(address(tUsdc));
            // path[1] = Currency.wrap(address(tUsdt));
            // uint256 amountIn = 2000 * baseDecimals(address(tUsdc));
            // safeApprove(usdc, address(router), amountIn);
            // swapExactInput(path, amountIn, deployer);
        }

        vm.stopPrank();

        console2.log('\n== Post balance ==');
        console2.log('USDT balance:', ERC20(usdt).balanceOf(deployer) / baseDecimals(usdt));
        console2.log('USDC balance:', ERC20(usdc).balanceOf(deployer) / baseDecimals(usdc));
        // console2.log('WETH balance:', ERC20(weth).balanceOf(deployer));
    }

    function universalRouterSwapExactInput(
        Currency[] memory _path,
        uint256 _amountIn,
        address _takeRecipient
    ) public {
        // Check Reduce path and get tokenIn, tokenOut
        (Currency[] memory path, address tokenIn, address tokenOut) = _getReducePath(_path);

        // Get Exact Input Params
        IV4Router.ExactInputParams memory params = _getExactInputParams(path, _amountIn);

        // Get Planner for path
        Plan memory planner = Planner.init();
        planner = planner.add(Actions.SWAP_EXACT_IN, abi.encode(params));
        planner = _getPlannerForPath(planner, path, _takeRecipient);
        bytes memory data = planner.encode();

        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.V4_SWAP)));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = data;

        uint256 beforeBalance = ERC20(tokenOut).balanceOf(deployer);

        universalRouter.execute{value: 0}(commands, inputs);

        uint256 afterBalance = ERC20(tokenOut).balanceOf(deployer);

        console2.log('\n== UniversalRouter Swap Exact In %d Hops ==', (path.length - 1));
        console2.log('TokenIn:', tokenIn);
        console2.log('TokenOut:', tokenOut);
        console2.log('AmountIn:', _amountIn);
        console2.log('AmountOut:', (afterBalance - beforeBalance));
    }

    function swapExactInput(
        Currency[] memory _path,
        uint256 _amountIn,
        address _takeRecipient
    ) public {
        // Check Reduce path and get tokenIn, tokenOut
        (Currency[] memory path, address tokenIn, address tokenOut) = _getReducePath(_path);

        // Get Exact Input Params
        IV4Router.ExactInputParams memory params = _getExactInputParams(path, _amountIn);

        // Get Planner for path
        Plan memory planner = Planner.init();
        planner = planner.add(Actions.SWAP_EXACT_IN, abi.encode(params));
        planner = _getPlannerForPath(planner, path, _takeRecipient);
        bytes memory data = planner.encode();

        uint256 beforeBalance = ERC20(tokenOut).balanceOf(deployer);

        router.executeActions(data);

        uint256 afterBalance = ERC20(tokenOut).balanceOf(deployer);

        console2.log('\n== Swap Exact In %d Hops ==', (path.length - 1));
        console2.log('TokenIn:', tokenIn);
        console2.log('TokenOut:', tokenOut);
        console2.log('AmountIn:', _amountIn);
        console2.log('AmountOut:', (afterBalance - beforeBalance));
    }

    function _getReducePath(Currency[] memory _path)
        public
        view
        returns (
            Currency[] memory path,
            address underlyingIn,
            address underlyingOut
        )
    {
        (bool isSupport0, address token0) = bank.getSupportUnderlyingByTokenize(Currency.unwrap(_path[0]));
        underlyingIn = isSupport0 ? token0 : Currency.unwrap(_path[0]);

        (bool isSupport1, address token1) = bank.getSupportUnderlyingByTokenize(
            Currency.unwrap(_path[_path.length - 1])
        );
        underlyingOut = isSupport1 ? token1 : Currency.unwrap(_path[_path.length - 1]);

        if (_path.length == 2) {
            return (_path, underlyingIn, underlyingOut);
        }

        // Find reduce path for
        // - first token is underlying of next tokenize
        // - last token is underlying of previous tokenize
        bool reduceFirst = false;
        bool reduceLast = false;
        if (!isSupport0) {
            (, address tokenizeIn) = bank.getSupportTokenizeByUnderlying(underlyingIn);
            reduceFirst = tokenizeIn == Currency.unwrap(_path[1]);
        }
        if (!isSupport1) {
            (, address tokenizeOut) = bank.getSupportTokenizeByUnderlying(underlyingOut);
            reduceLast = tokenizeOut == Currency.unwrap(_path[_path.length - 2]);
        }

        // No need to reduce
        if (!reduceFirst && !reduceLast) {
            return (_path, underlyingIn, underlyingOut);
        }

        // Copy reduce in new path
        uint256 pathLength = _path.length - (reduceFirst ? 1 : 0) - (reduceLast ? 1 : 0);
        path = new Currency[](pathLength);
        if (reduceFirst) {
            path[0] = _path[1];
        }
        if (reduceLast) {
            path[path.length - 1] = _path[_path.length - 2];
        }

        uint256 start = reduceFirst ? 1 : 0;
        uint256 end = reduceLast ? path.length - 1 : path.length;
        for (uint256 i = start; i < end; i++) {
            path[i] = _path[reduceFirst ? i + 1 : i];
        }
    }

    function _getPlannerForPath(
        Plan memory _planner,
        Currency[] memory _path,
        address _takeRecipient
    ) internal view returns (Plan memory) {
        (bool isSupport0, address token0) = bank.getSupportUnderlyingByTokenize(Currency.unwrap(_path[0]));

        // Pay currency in
        _planner = _planner.add(Actions.SETTLE, abi.encode(_path[0], ActionConstants.OPEN_DELTA, true));

        for (uint256 i = 1; i < _path.length; i++) {
            (bool isSupport1, address token1) = bank.getSupportUnderlyingByTokenize(Currency.unwrap(_path[i]));

            if (isSupport0 && Currency.unwrap(_path[i]) == token0) {
                _planner = _planner.add(
                    Actions.TAKE,
                    abi.encode(_path[i - 1], ActionConstants.ADDRESS_THIS, ActionConstants.OPEN_DELTA)
                );
                _planner = _planner.add(
                    Actions.SETTLE,
                    abi.encode(Currency.wrap(token0), ActionConstants.OPEN_DELTA, false)
                );
            } else if (isSupport1 && Currency.unwrap(_path[i - 1]) == token1) {
                _planner = _planner.add(
                    Actions.TAKE,
                    abi.encode(Currency.wrap(token1), ActionConstants.ADDRESS_THIS, ActionConstants.OPEN_DELTA)
                );
                _planner = _planner.add(Actions.SETTLE, abi.encode(_path[i], ActionConstants.OPEN_DELTA, false));
            }

            isSupport0 = isSupport1;
            token0 = token1;
        }

        // Take currency out
        _planner = _planner.add(
            Actions.TAKE,
            abi.encode(_path[_path.length - 1], _takeRecipient, ActionConstants.OPEN_DELTA)
        );
        return _planner;
    }

    function _getExactInputParams(Currency[] memory _tokenPath, uint256 amountIn)
        internal
        pure
        returns (IV4Router.ExactInputParams memory params)
    {
        PathKey[] memory path = new PathKey[](_tokenPath.length - 1);
        for (uint256 i = 0; i < _tokenPath.length - 1; i++) {
            path[i] = PathKey(_tokenPath[i + 1], 3000, 60, IHooks(address(0)), bytes(''));
        }

        params.currencyIn = _tokenPath[0];
        params.path = path;
        params.amountIn = uint128(amountIn);
        params.amountOutMinimum = 0;
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
