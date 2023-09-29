// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {LimiterConfig, LimiterConfigLib} from "../limiter/LimiterConfigLib.sol";

error DangerousMaxLoss();

function baseConfig() pure returns (LimiterConfig) {
    // Default is 2% for max loss (in WAD).
    return LimiterConfigLib.initNew({maxDrawWad: 0.02e18, mainWindow: 1 days, elasticWindow: 6 hours});
}

function baseConfig(uint256 maxLossWad) pure returns (LimiterConfig) {
    // Above 20% dangerous, mainly to curb human error.
    if (maxLossWad > 0.2e18) revert DangerousMaxLoss();
    return LimiterConfigLib.initNew({maxDrawWad: maxLossWad, mainWindow: 1 days, elasticWindow: 6 hours});
}

function baseConfig_unsafe(uint256 maxLossWad) pure returns (LimiterConfig) {
    return LimiterConfigLib.initNew({maxDrawWad: maxLossWad, mainWindow: 1 days, elasticWindow: 6 hours});
}
