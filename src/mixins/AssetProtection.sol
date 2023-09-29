// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {LimiterConfig} from "../limiter/LimiterConfigLib.sol";
import {DecreaseLimiter} from "../limiter/DecreaseLimiterLib.sol";
import {MainDSM} from "../dsm/MainDSM.sol";
import {FungibleAsset, NATIVE} from "../utils/FungibleAssetLib.sol";

/// @author philogy <https://github.com/philogy>
abstract contract AssetProtector is MainDSM {
    LimiterConfig internal immutable _DEFAULT_LIMITER_CONFIG;

    // @dev 30 minutes is already pretty low, a higher default delay is recommended
    uint256 internal constant _MIN_DELAY = 30 minutes;

    uint256 internal constant _UNLOCKED = 1;
    uint256 internal constant _LOCKED = 2;

    mapping(FungibleAsset => DecreaseLimiter) private _outflowLimiters;
    mapping(FungibleAsset => uint256) private _pendingOutflows;
    uint256 private _balanceDiffLock = _UNLOCKED;

    error NotContract();
    error DangerouslyLowDelay();
    error ReenteringBalanceDiff();

    constructor(LimiterConfig defaultConfig, uint40 startDelay) MainDSM(startDelay) {
        _DEFAULT_LIMITER_CONFIG = defaultConfig;
    }

    modifier diffReentrancyLock() {
        if (_balanceDiffLock == _LOCKED) revert ReenteringBalanceDiff();
        _balanceDiffLock = _LOCKED;
        _;
        _balanceDiffLock = _UNLOCKED;
    }

    modifier onlyThis() {
        if (msg.sender != address(this)) revert NotContract();
        _;
    }

    modifier recordsInflow() {
        _recordETHInflow();
        _;
    }

    function settleAsset(FungibleAsset asset, address to, uint256 amount) external onlyThis {
        asset.transfer(to, amount);
        _pendingOutflows[asset] -= amount;
    }

    function _recordETHInflow() internal {
        _recordInflow(NATIVE, msg.value, true);
    }

    function _safeTransferFrom(address token, address from, uint256 amount) internal {
        FungibleAsset asset = FungibleAsset.wrap(token);
        asset.transferFrom(from, address(this), amount);
        _recordInflow(asset, amount, true);
    }

    function _safeTransferFrom_feeOnTransfer_reentrancyUnsafe(address token, address from, uint256 amount) internal {
        FungibleAsset asset = FungibleAsset.wrap(token);
        uint256 balBefore = asset.balanceOfThis();
        // Tokens such as ERC777 that support custom callbacks on transfer can enable reentrancy
        // here, making the balance diff subject to double-counting of deposits. Use the
        // "reentrancySafe" variant if you want to support both fee-on-transfer and hook tokens.
        asset.transferFrom(from, address(this), amount);
        uint256 realInflow = asset.balanceOfThis() - balBefore;
        _recordInflow(asset, realInflow, true);
    }

    function _safeTransferFrom_feeOnTransfer_reentrancySafe(address token, address from, uint256 amount)
        internal
        diffReentrancyLock
    {
        FungibleAsset asset = FungibleAsset.wrap(token);
        uint256 balBefore = asset.balanceOfThis();
        // Tokens such as ERC777 that support custom callbacks on transfer can enable reentrancy
        // here, making the balance diff subject to double-counting of deposits. Use the
        // "reentrancySafe" variant if you want to support both fee-on-transfer and hook tokens.
        asset.transferFrom(from, address(this), amount);
        uint256 realInflow = asset.balanceOfThis() - balBefore;
        _recordInflow(asset, realInflow, true);
    }

    function _recordInflow(FungibleAsset asset, uint256 realInflow, bool postBalanceUpdate) private {
        uint256 overflow;
        uint256 preTvl = asset.balanceOfThis() - _pendingOutflows[asset] - (postBalanceUpdate ? realInflow : 0);
        (_outflowLimiters[asset], overflow) =
            _outflowLimiters[asset].applyInflow(_DEFAULT_LIMITER_CONFIG, preTvl, realInflow);
        assert(overflow == 0);
    }

    function _attemptTransfer(FungibleAsset asset, address to, uint256 amount) private {
        DecreaseLimiter limiter = _outflowLimiters[asset];
        uint256 prevPendingOutflows = _pendingOutflows[asset];
        uint256 preTvl = asset.balanceOfThis() - prevPendingOutflows;
        (DecreaseLimiter updatedLimiter, uint256 overflow) =
            limiter.applyOutflow(_DEFAULT_LIMITER_CONFIG, preTvl, amount);
        if (overflow == 0) {
            asset.transfer(to, amount);
            _outflowLimiters[asset] = updatedLimiter;
        } else {
            // Rate limiter exceeded, skip limiter update and delay settlement of entire transfer.
            _schedule(address(this), 0, abi.encodeCall(this.settleAsset, (asset, to, amount)));
            _pendingOutflows[asset] = prevPendingOutflows + amount;
        }
    }

    function _setDelay(uint40 delay) internal virtual override {
        if (delay < _MIN_DELAY) revert DangerouslyLowDelay();
        super._setDelay(delay);
    }
}
