// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {min, cappedSub} from "../utils/Math.sol";

/// @author philogy <https://github.com/philogy>
library LimiterMathLib {
    function depleteBuffers(uint256 mainBuffer, uint256 elasticBuffer, uint256 amount)
        internal
        pure
        returns (uint256 remMainBuffer, uint256 remElasticBuffer, uint256 remAmount)
    {
        remAmount = amount;
        (remElasticBuffer, remAmount) = depleteSub(elasticBuffer, remAmount);
        (remMainBuffer, remAmount) = depleteSub(mainBuffer, remAmount);
    }

    function depleteSub(uint256 buffer, uint256 amount) internal pure returns (uint256 remBuffer, uint256 remAmount) {
        remBuffer = cappedSub(buffer, amount);
        remAmount = cappedSub(amount, buffer);
    }

    function replenishMainBuffer(uint256 buffer, uint256 bufferCap, uint256 dt, uint256 replenishWindow)
        internal
        pure
        returns (uint256)
    {
        return min(bufferCap, buffer + bufferCap * dt / replenishWindow);
    }

    function decayElasticBuffer(uint256 elasticBuffer, uint256 dt, uint256 decayWindow)
        internal
        pure
        returns (uint256)
    {
        return cappedSub(elasticBuffer, elasticBuffer * dt / decayWindow);
    }
}
