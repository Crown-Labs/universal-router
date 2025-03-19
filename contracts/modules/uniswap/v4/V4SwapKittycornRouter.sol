// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import {UniswapImmutables} from '../UniswapImmutables.sol';
import {Permit2Payments} from '../../Permit2Payments.sol';
import {V4Router} from '@kittycorn/src/v4-periphery/V4Router.sol';
import {IPoolManager} from '@uniswap/v4-core/src/interfaces/IPoolManager.sol';
import {Currency} from '@uniswap/v4-core/src/types/Currency.sol';
import {ERC20} from 'solmate/src/tokens/ERC20.sol';
import {SafeTransferLib} from 'solmate/src/utils/SafeTransferLib.sol';
import {IKittycornBank} from '@kittycorn/src/interface/IKittycornBank.sol';

/// @title Router for Uniswap v4 Trades
abstract contract V4SwapKittycornRouter is V4Router, Permit2Payments {
    using SafeTransferLib for *;

    IKittycornBank public bank;

    constructor(address _poolManager, address _bank) V4Router(IPoolManager(_poolManager)) {
        bank = IKittycornBank(_bank);
    }

    // implementation of abstract function DeltaResolver._pay
    function _pay(
        Currency token,
        address payer,
        uint256 amount
    ) internal override {
        // Check if token is tokenize token
        (bool isSupport, address ulToken) = bank.getSupportUnderlyingByTokenize(Currency.unwrap(token));
        if (isSupport) {
            // Transfer underlying token to bank
            if (payer == address(this)) {
                ERC20(ulToken).safeTransfer(address(bank), amount);
            } else {
                PERMIT2.transferFrom(payer, address(bank), uint160(amount), ulToken);
            }

            // Deposit underlying token to tokenize
            bank.deposit(ulToken, amount);

            // Transfer tokenize token to poolManager
            token.transfer(address(poolManager), amount);
            return;
        }

        // Otherwise, transfer token to poolManager directly
        if (payer == address(this)) {
            token.transfer(address(poolManager), amount);
        } else {
            PERMIT2.transferFrom(payer, address(poolManager), uint160(amount), Currency.unwrap(token));
        }
    }

    // implementation of abstract function DeltaResolver._collect
    function _collect(
        Currency token,
        address receiver,
        uint256 amount
    ) internal override {
        // Transfer token from poolManager to this router
        poolManager.take(token, address(this), amount);

        // Check if token is tokenize token
        (bool isSupport, address ulToken) = bank.getSupportUnderlyingByTokenize(Currency.unwrap(token));
        if (isSupport) {
            // Withdraw underlying token from tokenize
            address tokenize = Currency.unwrap(token);
            bank.withdraw(tokenize, amount);

            token = Currency.wrap(ulToken);
        }

        // Optimize skip transfer if receiver is this router
        if (receiver == address(this)) {
            return;
        }

        // Transfer token to receiver
        ERC20(Currency.unwrap(token)).safeTransfer(receiver, amount);
    }

    // implementation of abstract function BaseActionsRouter.checkTokenizeInCurrencyPath
    function checkTokenizeInCurrencyPath(Currency currency0, Currency currency1) public view override returns (bool) {
        (bool isTokenize, address ulToken) = bank.getSupportUnderlyingByTokenize(Currency.unwrap(currency0));
        if (isTokenize && Currency.unwrap(currency1) == ulToken) {
            return true;
        }
        (isTokenize, ulToken) = bank.getSupportUnderlyingByTokenize(Currency.unwrap(currency1));
        if (isTokenize && Currency.unwrap(currency0) == ulToken) {
            return true;
        }
        return false;
    }
}
