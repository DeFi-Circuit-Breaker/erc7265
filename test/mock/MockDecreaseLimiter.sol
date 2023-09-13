// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {SafeCastLib} from "solady/utils/SafeCastLib.sol";
import {DecreaseLimiterLib, DecreaseLimiter, DecreaseResult} from "src/limiter/DecreaseLimiterLib.sol";
import {LimiterConfigLib, LimiterConfig} from "src/limiter/LimiterConfigLib.sol";

/// @author philogy <https://github.com/philogy>
contract MockDecreaseLimiter {
    using SafeCastLib for uint256;

    LimiterConfig internal immutable config;

    DecreaseLimiter internal limiter;

    uint256 public tvl;

    error InvalidAmount();

    error LimiterExceeded();

    constructor(uint256 maxDrawWad, uint256 mainWindow, uint256 elasticWindow) {
        config = LimiterConfigLib.initNew(maxDrawWad, mainWindow, elasticWindow);
    }

    function trackedInflow(uint256 amount) external {
        limiter = limiter.recordFlow({config: config, preReserves: tvl, flow: amount.toInt256()}).unwrap();
        tvl += amount;
    }

    function untrackedInflow(uint256 amount) external {
        tvl += amount;
    }

    function trackedOutflow(uint256 amount) external {
        if (amount > tvl) revert InvalidAmount();
        DecreaseResult result = limiter.recordFlow({config: config, preReserves: tvl, flow: -amount.toInt256()});
        if (result.isErr()) revert LimiterExceeded();
        limiter = result.unwrap();
        tvl -= amount;
    }

    function update() external {
        limiter = limiter.update(config);
    }

    function getRaw() external view returns (uint256 lastUpdatedAt, uint256 relMainBuffer, uint256 relElastic) {
        return limiter.unpack();
    }

    function getMaxFlow() external view returns (uint256 maxMainFlow, uint256 maxElasticDeplete) {
        return limiter.update(config).getMaxFlow(config, tvl);
    }
}
