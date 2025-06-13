// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import 'forge-std/console2.sol';
import {Script} from 'forge-std/Script.sol';
import 'forge-std/Test.sol';
import {RouterParameters} from 'contracts/types/RouterParameters.sol';
import {IAllowanceTransfer} from 'v4-periphery/lib/permit2/src/interfaces/IAllowanceTransfer.sol';
import {IV4Router} from 'v4-periphery/src/interfaces/IV4Router.sol';
import {IHooks} from 'v4-core/src/interfaces/IHooks.sol';
import {PathKey} from 'v4-periphery/src/libraries/PathKey.sol';
import {PoolKey} from 'v4-core/src/types/PoolKey.sol';
import {Constants} from 'v4-core/test/utils/Constants.sol';
import {Currency, CurrencyLibrary} from 'v4-core/src/types/Currency.sol';
import {Plan, Planner} from 'v4-periphery/test/shared/Planner.sol';
import {Actions} from 'v4-periphery/src/libraries/Actions.sol';
import {ActionConstants} from 'v4-periphery/src/libraries/ActionConstants.sol';
import {UniversalRouter} from '../contracts/UniversalRouter.sol';
import {Commands} from '../contracts/libraries/Commands.sol';
import {KittycornBank} from '@kittycorn/src/core/KittycornBank.sol';
import {KittycornRouter} from '@kittycorn/src/KittycornRouter.sol';
import {Tokenize} from '@kittycorn/src/tokenize/Tokenize.sol';
import {ERC20} from 'solmate/src/tokens/ERC20.sol';
import {SafeTransferLib} from 'solmate/src/utils/SafeTransferLib.sol';

contract KittycornUniversalRouterTest is Script, Test {
    using SafeTransferLib for *;

    address deployer;
    address usdt;
    address usdc;
    address weth;
    address wbtc;

    UniversalRouter universalRouter;
    KittycornRouter router;
    KittycornBank bank;
    IAllowanceTransfer permit2;

    Tokenize tUsdt;
    Tokenize tUsdc;
    Tokenize tWeth;
    Tokenize tWbtc;

    function setUp() public {
        deployer = msg.sender;

        // Deploy Universal-router Sepolia
        permit2 = IAllowanceTransfer(0x000000000022D473030F116dDEE9F6B43aC78BA3);
        router = KittycornRouter(payable(0x7678CE633dFBD754A84D38ed7A8F172efDF88D5C));
        bank = KittycornBank(address(router.bank()));

        RouterParameters memory params = RouterParameters({
            permit2: 0x000000000022D473030F116dDEE9F6B43aC78BA3,
            weth9: 0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c,
            v2Factory: 0xB7f907f7A9eBC822a80BD25E224be42Ce0A698A0,
            v3Factory: 0x0227628f3F023bb0B980b67D528571c95c6DaC1c,
            pairInitCodeHash: 0x96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f,
            poolInitCodeHash: 0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54,
            v4PoolManager: 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543,
            v3NFTPositionManager: 0x1238536071E1c677A632429e3655c799b22cDA52,
            v4PositionManager: 0x9217f722bcd5812FA14538BFDc5f2c4D0546594e,
            kittycornBank: address(bank)
        });
        universalRouter = new UniversalRouter(params);
        // universalRouter = UniversalRouter(payable(0x885a501cbe18B50083AC8ef33ddab81CB5226cAA));

        usdt = 0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0;
        usdc = 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8;
        weth = 0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c;
        wbtc = 0x29f2D40B0605204364af54EC677bD022dA425d03;

        tUsdt = Tokenize(0x137a906E06EC20808c8F156F9024196427429220);
        tUsdc = Tokenize(0x1E271DB8D8B446A0DEe8e9D774f4213e9Bc1C6ba);
        tWeth = Tokenize(0x54f4d76DaB01190A32FB0a5da441Be85e3Cef937);
        tWbtc = Tokenize(0x67332E6e2fbB793B822f3c2d7ff8BE9F07F1eAd9);

        vm.label(address(deployer), 'Deployer');
        vm.label(address(permit2), 'Permit2');
        vm.label(address(universalRouter), 'UniversalRouter');
        vm.label(address(router), 'KittycornRouter');
        vm.label(address(bank), 'KittycornBank');
        vm.label(usdt, 'USDT');
        vm.label(usdc, 'USDC');
        vm.label(weth, 'WETH');
        vm.label(wbtc, 'WBTC');
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
        // deal(weth, deployer, 2_000 * baseDecimals(weth));

        console2.log('\n== Initial balance ==');
        console2.log('Initial ETH balance:', deployer.balance / 1 ether);
        console2.log('Initial USDT balance:', ERC20(usdt).balanceOf(deployer) / baseDecimals(usdt));
        console2.log('Initial USDC balance:', ERC20(usdc).balanceOf(deployer) / baseDecimals(usdc));
        console2.log('Initial WETH balance:', ERC20(weth).balanceOf(deployer) / baseDecimals(weth));
        console2.log('Initial WBTC balance:', ERC20(wbtc).balanceOf(deployer) / baseDecimals(wbtc));
    }

    function run() public {
        vm.startPrank(deployer);

        // UniversalRouter swap native
        {
            Currency[] memory path = new Currency[](4);
            path[0] = CurrencyLibrary.ADDRESS_ZERO; // Native token (ETH)
            path[1] = Currency.wrap(address(weth));
            path[2] = Currency.wrap(address(tWeth));
            path[3] = Currency.wrap(address(tWbtc));
            uint256 amountIn = (5 * baseDecimals(address(weth))) / 10000; // 0.0005 ETH
            universalRouterSwapNativeExactInput(path, amountIn, deployer);
        }

        // UniversalRouter swap with permit
        {
            safeApprove(weth, address(permit2), type(uint256).max);

            Currency[] memory path = new Currency[](2);
            path[0] = Currency.wrap(address(tWeth));
            path[1] = Currency.wrap(address(tWbtc));
            uint256 amountIn = (1 * baseDecimals(address(tWeth))) / 100; // 0.01 weth
            universalRouterSwapExactInput(path, amountIn, deployer);
        }

        // KittycornRouter
        {
            Currency[] memory path = new Currency[](2);
            path[0] = Currency.wrap(address(tWeth));
            path[1] = Currency.wrap(address(tWbtc));
            uint256 amountIn = (1 * baseDecimals(address(tWeth))) / 100; // 0.01 weth
            safeApprove(weth, address(router), amountIn);
            swapExactInput(path, amountIn, deployer);
        }

        vm.stopPrank();

        console2.log('\n== Post balance ==');
        console2.log('USDT balance:', ERC20(usdt).balanceOf(deployer) / baseDecimals(usdt));
        console2.log('USDC balance:', ERC20(usdc).balanceOf(deployer) / baseDecimals(usdc));
        console2.log('WETH balance:', ERC20(weth).balanceOf(deployer) / baseDecimals(weth));
        console2.log('WBTC balance:', ERC20(wbtc).balanceOf(deployer) / baseDecimals(wbtc));
    }

    function universalRouterSwapNativeExactInput(
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

        uint256 beforeBalanceOut = path[path.length - 1].isAddressZero()
            ? _takeRecipient.balance
            : ERC20(tokenOut).balanceOf(_takeRecipient);

        uint256 value = path[0].isAddressZero() ? _amountIn : 0;
        universalRouter.execute{value: value}(commands, inputs);

        uint256 afterBalanceOut = path[path.length - 1].isAddressZero()
            ? _takeRecipient.balance
            : ERC20(tokenOut).balanceOf(_takeRecipient);

        console2.log('\n== UniversalRouter Swap Native Exact Input %d Hops ==', (path.length - 1));
        console2.log('TokenIn:', tokenIn);
        console2.log('TokenOut:', tokenOut);
        console2.log('AmountIn:', _amountIn);
        console2.log('AmountOut:', (afterBalanceOut - beforeBalanceOut));
    }

    function universalRouterSwapExactInput(
        Currency[] memory _path,
        uint256 _amountIn,
        address _takeRecipient
    ) public {
        // Check Reduce path and get tokenIn, tokenOut
        (Currency[] memory path, address tokenIn, address tokenOut) = _getReducePath(_path);

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
        IV4Router.ExactInputParams memory params = _getExactInputParams(path, _amountIn);

        // Get Planner for path
        Plan memory planner = Planner.init();
        planner = planner.add(Actions.SWAP_EXACT_IN, abi.encode(params));
        planner = _getPlannerForPath(planner, path, _takeRecipient);
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

        uint256 beforeBalanceOut = path[path.length - 1].isAddressZero()
            ? _takeRecipient.balance
            : ERC20(tokenOut).balanceOf(_takeRecipient);

        uint256 value = path[0].isAddressZero() ? _amountIn : 0;
        router.executeActions{value: value}(data);

        uint256 afterBalanceOut = path[path.length - 1].isAddressZero()
            ? _takeRecipient.balance
            : ERC20(tokenOut).balanceOf(_takeRecipient);

        console2.log('\n== Router Swap Exact Input %d Hops ==', (path.length - 1));
        console2.log('TokenIn:', tokenIn);
        console2.log('TokenOut:', tokenOut);
        console2.log('AmountIn:', _amountIn);
        console2.log('AmountOut:', (afterBalanceOut - beforeBalanceOut));
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
            path[i] = PathKey(_tokenPath[i + 1], 100, 1, IHooks(address(0)), bytes(''));
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
