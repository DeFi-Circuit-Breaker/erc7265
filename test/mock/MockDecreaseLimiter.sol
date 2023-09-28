// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {SafeCastLib} from "solady/utils/SafeCastLib.sol";
import {DecreaseLimiterLib, DecreaseLimiter} from "src/limiter/DecreaseLimiterLib.sol";
import {LimiterConfigLib, LimiterConfig} from "src/limiter/LimiterConfigLib.sol";

/// @author philogy <https://github.com/philogy>
contract MockDecreaseLimiter {
    using SafeCastLib for uint256;

    LimiterConfig internal immutable config;

    DecreaseLimiter internal limiter;

    uint256 public tvl;

    error InvalidAmount();

    error LimiterExceeded();

    constructor(uint256 maxDrawWad, uint256 mainWindow, uint256 elasticWindow, uint256 startTvl) {
        config = LimiterConfigLib.initNew(maxDrawWad, mainWindow, elasticWindow);
        tvl = startTvl;
    }

    function trackedInflow(uint256 amount) external {
        uint256 overflow;
        (limiter, overflow) = limiter.applyInflow(config, tvl, amount);
        assert(overflow == 0);
        tvl += amount;
    }

    function untrackedInflow(uint256 amount) external {
        tvl += amount;
    }

    function trackedOutflow(uint256 amount) external {
        if (amount > tvl) revert InvalidAmount();
        (DecreaseLimiter updatedLimiter, uint256 overflow) = limiter.applyOutflow(config, tvl, amount);
        if (overflow > 0) revert LimiterExceeded();
        limiter = updatedLimiter;
        tvl -= amount;
    }

    function update() external {
        limiter = limiter.applyUpdate(config, tvl);
    }

    function getRaw() external view returns (uint256 lastUpdatedAt, uint256 relMainBuffer, uint256 relElastic) {
        return limiter.getState().unpack();
    }

    function getMaxFlow() external view returns (uint256 maxMainFlow, uint256 maxElasticDeplete) {
        return limiter._getPassivelyUpdatedBuffers(config, tvl, block.timestamp);
    }
}
