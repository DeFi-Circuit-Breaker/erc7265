// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {FixedPointMathLib as Math} from "solady/utils/FixedPointMathLib.sol";

/// @author philogy <https://github.com/philogy>
library DelayLib {
    function getNewValidity(uint256 currentDelay, uint256 validSince) internal view returns (uint256) {
        return Math.max(block.timestamp - currentDelay, validSince);
    }

    function getSettlementTime(uint256 scheduledAt, uint256 originalDelay, uint256 currentDelay, uint256 validSince)
        internal
        pure
        returns (uint256)
    {
        uint256 originalSettlement = scheduledAt + originalDelay;
        return originalSettlement >= validSince ? scheduledAt + currentDelay : originalSettlement;
    }
}
