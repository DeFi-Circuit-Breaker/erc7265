// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {LimiterConfig} from "../limiter/LimiterConfigLib.sol";
import {DecreaseLimiter} from "../limiter/DecreaseLimiterLib.sol";
import {MainDSM} from "../dsm/MainDSM.sol";

/// @author philogy <https://github.com/philogy>
abstract contract AssetProtector is MainDSM {
    LimiterConfig internal immutable _DEFAULT_LIMITER_CONFIG;

    // @dev 30 minutes is already pretty low, a higher default delay is recommended
    uint internal constant _MIN_DELAY = 30 minutes;

    error NotContract();
    error DangerouslyLowDelay();

    constructor(LimiterConfig defaultConfig, uint40 startDelay)
        MainDSM(startDelay)
    {
        _DEFAULT_LIMITER_CONFIG = defaultConfig;
    }

    modifier onlyThis() {
        if (msg.sender != address(this)) revert NotContract();
        _;
    }

    function _setDelay(uint40 delay) internal virtual override {
        if (delay < _MIN_DELAY) revert DangerouslyLowDelay();
        super._setDelay(delay);
    }
}
