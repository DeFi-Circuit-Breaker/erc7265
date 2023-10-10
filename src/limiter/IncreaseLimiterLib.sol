// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {LimiterStateLib, LimiterState} from "./LimiterStateLib.sol";
import {LimiterConfig} from "./LimiterConfigLib.sol";

type IncreaseLimiter is uint256;

/// @author philogy <https://github.com/philogy>
library IncreaseLimiterLib {
    using FixedPointMathLib for uint256;

    error MainBufferAboveMax();

    function _fromState(LimiterState state) internal pure returns (IncreaseLimiter limiter) {
        return IncreaseLimiter.wrap(LimiterState.unwrap(state));
    }

    function initNew(uint256 lastUpdatedAt, uint256 initialTvl, LimiterConfig config)
        internal
        pure
        returns (IncreaseLimiter limiter)
    {
        return _fromState(
            LimiterStateLib.pack(
                lastUpdatedAt, mainBufferToRepr(0, initialTvl, config), elasticBufferToRepr(0, initialTvl, config)
            )
        );
    }

    function initNew(
        uint256 lastUpdatedAt,
        uint256 mainBuffer,
        uint256 elasticBuffer,
        uint256 tvl,
        LimiterConfig config
    ) internal pure returns (IncreaseLimiter) {
        return _fromState(
            LimiterStateLib.pack(
                lastUpdatedAt,
                mainBufferToRepr(mainBuffer, tvl, config),
                elasticBufferToRepr(elasticBuffer, tvl, config)
            )
        );
    }

    function getState(IncreaseLimiter limiter) internal pure returns (LimiterState state) {
        return LimiterState.wrap(IncreaseLimiter.unwrap(limiter));
    }

    function mainBufferToRepr(uint256 buffer, uint256 tvl, LimiterConfig config) internal pure returns (uint256 repr) {
        uint256 maxDrawWad = config.getMaxDrawWad();
        uint256 maxBuffer = tvl.mulWad(maxDrawWad);
        if (buffer > maxBuffer) revert MainBufferAboveMax();
        repr = maxBuffer == 0 ? 0 : buffer.divWad(maxBuffer);
    }

    function mainBufferFromRepr(uint256 repr, uint256 tvl, LimiterConfig config)
        internal
        pure
        returns (uint256 buffer)
    {
        uint256 maxDrawWad = config.getMaxDrawWad();
        buffer = tvl.mulWad(maxDrawWad).mulWad(repr);
    }

    function elasticBufferToRepr(uint256 buffer, uint256 tvl, LimiterConfig) internal pure returns (uint256 repr) {
        repr = tvl == 0 ? 0 : buffer.divWad(buffer + tvl);
    }

    function elasticBufferFromRepr(uint256 repr, uint256 tvl, LimiterConfig) internal pure returns (uint256 buffer) {
        buffer = tvl.mulWad(repr);
    }
}
