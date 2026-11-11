// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from 'forge-std/Test.sol';
import {KittycornUniversalRouter} from 'contracts/KittycornUniversalRouter.sol';
import {RouterParameters} from 'contracts/types/RouterParameters.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {WETH} from 'solmate/src/tokens/WETH.sol';

contract Permit2Mock {
    mapping(address => mapping(address => uint160)) public allowance;

    function approve(address, address spender, uint160 amount, uint48) external {
        allowance[msg.sender][spender] = amount;
    }

    function transferFrom(address from, address to, uint160 amount, address token) external {
        require(allowance[from][msg.sender] >= amount, 'PERMIT2_ALLOWANCE');
        allowance[from][msg.sender] -= amount;
        IERC20(token).transferFrom(from, to, amount);
    }
}

contract FundingToken is ERC20 {
    bool public fee;

    function enableFee() external {
        fee = true;
    }

    function _update(address from, address to, uint256 amount) internal override {
        if (fee && from != address(0) && to != address(0) && amount > 0) {
            super._update(from, to, amount - 1);
            super._update(from, address(0), 1);
        } else {
            super._update(from, to, amount);
        }
    }
    constructor() ERC20('Test', 'TEST') {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract ActionRouterMock {
    address public constant poolManager = address(0x1234);
    address public constant WETH9 = address(0x5678);
    address public immutable bank;
    bool public reenter;

    function setReenter() external {
        reenter = true;
    }

    constructor() {
        bank = msg.sender;
    }

    function executeActions(bytes calldata data) external payable {
        (address token, uint256 spend, address receiver, bool fail) =
            abi.decode(data, (address, uint256, address, bool));
        require(!fail, 'SWAP_FAILED');
        if (reenter) {
            bytes[] memory inputs = new bytes[](0);
            (bool success,) = msg.sender.call(abi.encodeWithSignature('execute(bytes,bytes[])', bytes(''), inputs));
            require(!success, 'REENTRY_SUCCEEDED');
        }
        IERC20(token).transferFrom(msg.sender, receiver, spend);
    }
}

contract KittycornUniversalRouterTest is Test {
    KittycornUniversalRouter router;
    ActionRouterMock target;
    FundingToken token;
    Permit2Mock permit2;
    address user = address(0xa11ce);
    address receiver = address(0xb0b);

    function setUp() public {
        token = new FundingToken();
        permit2 = new Permit2Mock();
        target = new ActionRouterMock();
        RouterParameters memory params;
        params.permit2 = address(permit2);
        params.weth9 = target.WETH9();
        params.v4PoolManager = target.poolManager();
        router = new KittycornUniversalRouter(params, address(target));
        token.mint(user, 1_000_000);
        vm.startPrank(user);
        token.approve(address(permit2), type(uint256).max);
        permit2.approve(address(token), address(router), type(uint160).max, type(uint48).max);
        vm.stopPrank();
    }

    function plan(uint256 maximum, uint256 spend, bool payerIsUser, bool fail)
        internal
        view
        returns (bytes[] memory inputs)
    {
        inputs = new bytes[](1);
        inputs[0] = abi.encode(address(token), maximum, payerIsUser, abi.encode(address(token), spend, receiver, fail));
    }

    function testFuzz_UserFundsRefundAndClearAllowance(uint96 spend, uint96 extra) public {
        spend = uint96(bound(spend, 1, 500_000));
        extra = uint96(bound(extra, 0, 500_000));
        token.mint(address(router), 77);
        vm.prank(user);
        router.execute(hex'41', plan(uint256(spend) + extra, spend, true, false), block.timestamp);
        assertEq(token.balanceOf(user), 1_000_000 - spend);
        assertEq(token.balanceOf(receiver), spend);
        assertEq(token.balanceOf(address(router)), 77);
        assertEq(token.allowance(address(router), address(target)), 0);
    }

    function test_RouterBalanceFundsOnlyBudget() public {
        token.mint(address(router), 200);
        vm.prank(user);
        router.execute(hex'41', plan(100, 70, false, false), block.timestamp);
        assertEq(token.balanceOf(address(router)), 130);
        assertEq(token.balanceOf(user), 1_000_000);
        assertEq(token.allowance(address(router), address(target)), 0);
    }

    function test_CannotSpendAboveBudgetOrUseExistingBalance() public {
        token.mint(address(router), 500);
        vm.expectRevert();
        vm.prank(user);
        router.execute(hex'41', plan(100, 101, true, false), block.timestamp);
        assertEq(token.balanceOf(address(router)), 500);
        assertEq(token.balanceOf(user), 1_000_000);
        assertEq(token.allowance(address(router), address(target)), 0);
    }

    function test_CannotPullAnotherUsersPermit2Approval() public {
        vm.expectRevert();
        vm.prank(address(0xbad));
        router.execute(hex'41', plan(100, 100, true, false), block.timestamp);
        assertEq(token.balanceOf(user), 1_000_000);
    }

    function test_DeadlineAndSwapFailureAreAtomic() public {
        vm.warp(100);
        vm.expectRevert();
        vm.prank(user);
        router.execute(hex'41', plan(100, 100, true, false), 99);
        vm.expectRevert('SWAP_FAILED');
        vm.prank(user);
        router.execute(hex'41', plan(100, 100, true, true), 100);
        assertEq(token.balanceOf(user), 1_000_000);
        assertEq(token.allowance(address(router), address(target)), 0);
    }

    function test_RejectZeroFundingAndInvalidTarget() public {
        vm.expectRevert(KittycornUniversalRouter.InvalidKittycornFunding.selector);
        router.execute(hex'41', plan(0, 0, true, false), block.timestamp);
        RouterParameters memory params;
        params.permit2 = address(permit2);
        vm.expectRevert(KittycornUniversalRouter.InvalidKittycornRouter.selector);
        new KittycornUniversalRouter(params, address(target));
    }

    function test_RejectFeeOnTransferFundingAtomically() public {
        token.enableFee();
        vm.expectRevert(KittycornUniversalRouter.InvalidKittycornFunding.selector);
        vm.prank(user);
        router.execute(hex'41', plan(100, 50, true, false), block.timestamp);
        assertEq(token.balanceOf(user), 1_000_000);
        assertEq(token.balanceOf(address(router)), 0);
    }

    function test_CallbackCannotReenterExecute() public {
        target.setReenter();
        vm.prank(user);
        router.execute(hex'41', plan(100, 50, true, false), block.timestamp);
        assertEq(token.balanceOf(receiver), 50);
        assertEq(token.balanceOf(user), 999_950);
    }

    function test_DeploymentFitsEIP170() public view {
        assertLe(address(router).code.length, 24_576);
    }

    function test_UpstreamSweepCommandStillWorks() public {
        token.mint(address(router), 50);
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(address(token), receiver, uint256(50));
        router.execute(hex'04', inputs, block.timestamp);
        assertEq(token.balanceOf(receiver), 50);
    }

    /// @notice A sub-plan must retain the external payer for Permit2 funding and refunds.
    function test_SubPlanKeepsOriginalPayer() public {
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(hex'41', plan(100, 70, true, false));
        vm.prank(user);
        router.execute(hex'21', inputs, block.timestamp);
        assertEq(token.balanceOf(user), 999_930);
        assertEq(token.balanceOf(receiver), 70);
        assertEq(token.balanceOf(address(router)), 0);
        assertEq(token.allowance(address(router), address(target)), 0);
    }

    /// @notice Failure of a later command rolls back prior funding, swaps and refunds.
    function test_MultipleCommandsRollbackAtomically() public {
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = plan(100, 70, true, false)[0];
        inputs[1] = plan(100, 50, true, true)[0];
        vm.expectRevert('SWAP_FAILED');
        vm.prank(user);
        router.execute(hex'4141', inputs, block.timestamp);
        assertEq(token.balanceOf(user), 1_000_000);
        assertEq(token.balanceOf(receiver), 0);
        assertEq(token.balanceOf(address(router)), 0);
        assertEq(token.allowance(address(router), address(target)), 0);
    }

    /// @notice An allowed-to-fail sub-plan cannot leave funds or approvals behind.
    function test_AllowedSubPlanFailureRestoresFunding() public {
        token.mint(address(router), 77);
        bytes[] memory nested = new bytes[](2);
        nested[0] = plan(100, 70, true, false)[0];
        nested[1] = plan(100, 50, true, true)[0];
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(hex'4141', nested);
        vm.prank(user);
        router.execute(hex'a1', inputs, block.timestamp);
        assertEq(token.balanceOf(user), 1_000_000);
        assertEq(token.balanceOf(receiver), 0);
        assertEq(token.balanceOf(address(router)), 77);
        assertEq(token.allowance(address(router), address(target)), 0);
    }

    /// @notice Like V4_SWAP, a directly dispatched Kittycorn failure cannot be suppressed by its flag.
    function test_DirectAllowRevertFlagDoesNotSuppressFailure() public {
        vm.expectRevert('SWAP_FAILED');
        vm.prank(user);
        router.execute(hex'c1', plan(100, 70, true, true), block.timestamp);
        assertEq(token.balanceOf(user), 1_000_000);
        assertEq(token.allowance(address(router), address(target)), 0);
    }

    /// @notice Funding one currency cannot authorize spending another currency held by the router.
    function test_ActionCannotSpendAnotherToken() public {
        FundingToken other = new FundingToken();
        other.mint(address(router), 100);
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(address(token), 100, true, abi.encode(address(other), 50, receiver, false));
        vm.expectRevert();
        vm.prank(user);
        router.execute(hex'41', inputs, block.timestamp);
        assertEq(other.balanceOf(address(router)), 100);
        assertEq(other.balanceOf(receiver), 0);
        assertEq(token.balanceOf(user), 1_000_000);
        assertEq(token.allowance(address(router), address(target)), 0);
    }

    /// @notice Permit2's uint160 amount must reject overflow instead of truncating the funding cap.
    function test_Permit2FundingOverflowReverts() public {
        vm.expectRevert();
        vm.prank(user);
        router.execute(hex'41', plan(uint256(type(uint160).max) + 1, 1, true, false), block.timestamp);
        assertEq(token.balanceOf(user), 1_000_000);
        assertEq(token.allowance(address(router), address(target)), 0);
    }

    /// @notice Native funding never needs Permit2 and refunds unused ETH to the payer, not the token recipient.
    function testFuzz_NativeFundingRefundsPayer(uint96 spend, uint96 extra) public {
        spend = uint96(bound(spend, 1, 500_000));
        extra = uint96(bound(extra, 0, 500_000));
        vm.etch(target.WETH9(), address(new WETH()).code);
        WETH weth = WETH(payable(target.WETH9()));
        vm.deal(user, 1_000_000);
        uint256 maximum = uint256(spend) + extra;
        bytes[] memory inputs = new bytes[](3);
        inputs[0] = abi.encode(address(router), maximum);
        inputs[1] = abi.encode(address(weth), maximum, false, abi.encode(address(weth), spend, receiver, false));
        inputs[2] = abi.encode(address(1), uint256(0));
        vm.prank(user);
        router.execute{value: maximum}(hex'0b410c', inputs, block.timestamp);
        assertEq(user.balance, 1_000_000 - spend);
        assertEq(weth.balanceOf(receiver), spend);
        assertEq(receiver.balance, 0);
        assertEq(weth.balanceOf(address(router)), 0);
        assertEq(address(router).balance, 0);
        assertEq(weth.allowance(address(router), address(target)), 0);
    }

    /// @notice Failure of the final native minimum rolls back wrapping, spending and allowances atomically.
    function test_NativeUnwrapMinimumFailureRollsBack() public {
        vm.etch(target.WETH9(), address(new WETH()).code);
        WETH weth = WETH(payable(target.WETH9()));
        vm.deal(user, 1_000_000);
        bytes[] memory inputs = new bytes[](3);
        inputs[0] = abi.encode(address(router), uint256(100));
        inputs[1] =
            abi.encode(address(weth), uint256(100), false, abi.encode(address(weth), uint256(70), receiver, false));
        inputs[2] = abi.encode(address(1), uint256(31));
        vm.expectRevert();
        vm.prank(user);
        router.execute{value: 100}(hex'0b410c', inputs, block.timestamp);
        assertEq(user.balance, 1_000_000);
        assertEq(weth.balanceOf(receiver), 0);
        assertEq(weth.balanceOf(address(router)), 0);
        assertEq(address(router).balance, 0);
        assertEq(weth.allowance(address(router), address(target)), 0);
    }
}
