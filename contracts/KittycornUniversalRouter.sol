// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import {UniversalRouter} from './UniversalRouter.sol';
import {RouterParameters} from './types/RouterParameters.sol';
import {Commands} from './libraries/Commands.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

/// @notice Current Kittycorn action router. Accounting remains in this deployed contract.
interface IKittycornActionRouter {
    function executeActions(bytes calldata params) external payable;
    function poolManager() external view returns (address);
    function WETH9() external view returns (address);
    function bank() external view returns (address);
}

/// @notice Universal Router with Permit2 funding for Kittycorn's ERC4626 swaps.
/// @dev Command 0x41 encodes (inputToken, maximumInput, payerIsUser, actionPlan).
///      V4_SWAP keeps upstream semantics; conversion paths must use KITTYCORN_SWAP.
contract KittycornUniversalRouter is UniversalRouter {
    using SafeERC20 for IERC20;

    uint256 public constant KITTYCORN_SWAP = 0x41;
    IKittycornActionRouter public immutable kittycornRouter;

    error InvalidKittycornRouter();
    error InvalidKittycornFunding();
    error KittycornBalanceSpent();

    /// @param params Standard upstream router dependencies.
    /// @param router Existing KittycornRouter for the same PoolManager and WETH.
    constructor(RouterParameters memory params, address router) UniversalRouter(params) {
        if (router.code.length == 0) revert InvalidKittycornRouter();
        IKittycornActionRouter target = IKittycornActionRouter(router);
        if (
            target.poolManager() != params.v4PoolManager || target.WETH9() != params.weth9
                || target.bank().code.length == 0
        ) revert InvalidKittycornRouter();
        kittycornRouter = target;
    }

    /// @notice Execute Kittycorn's reserved integration command or dispatch upstream commands unchanged.
    /// @param commandType Command byte, including any allow-revert flag.
    /// @param inputs ABI encoded command parameters.
    /// @return success Whether the command succeeded.
    /// @return output Upstream command result data.
    function dispatch(bytes1 commandType, bytes calldata inputs)
        internal
        override
        returns (bool success, bytes memory output)
    {
        if (uint8(commandType & Commands.COMMAND_TYPE_MASK) != KITTYCORN_SWAP) {
            return super.dispatch(commandType, inputs);
        }
        (address token, uint256 maximumInput, bool payerIsUser, bytes memory actions) =
            abi.decode(inputs, (address, uint256, bool, bytes));
        _kittycornSwap(IERC20(token), maximumInput, payerIsUser, actions);
        return (true, bytes(''));
    }

    /// @notice Fund one action plan, cap its allowance, and refund only this command's unspent input.
    /// @param token Underlying ERC20 approved by the payer.
    /// @param maximumInput Maximum underlying amount the action router may spend.
    /// @param payerIsUser Use Permit2 when true, otherwise spend the Universal Router's balance.
    /// @param actions Encoded KittycornRouter action plan with its own output/price limits.
    function _kittycornSwap(IERC20 token, uint256 maximumInput, bool payerIsUser, bytes memory actions) private {
        if (maximumInput == 0) revert InvalidKittycornFunding();
        uint256 balanceBefore = token.balanceOf(address(this));
        if (payerIsUser) {
            payOrPermit2Transfer(address(token), msgSender(), address(this), maximumInput);
            if (token.balanceOf(address(this)) != balanceBefore + maximumInput) revert InvalidKittycornFunding();
        } else if (balanceBefore < maximumInput) {
            revert InvalidKittycornFunding();
        }
        token.forceApprove(address(kittycornRouter), maximumInput);
        kittycornRouter.executeActions(actions);
        token.forceApprove(address(kittycornRouter), 0);
        uint256 balanceAfter = token.balanceOf(address(this));
        uint256 minimumBalance = payerIsUser ? balanceBefore : balanceBefore - maximumInput;
        if (balanceAfter < minimumBalance) revert KittycornBalanceSpent();
        if (payerIsUser && balanceAfter > balanceBefore) token.safeTransfer(msgSender(), balanceAfter - balanceBefore);
    }
}
