// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

type LimiterState is uint256;

using LimiterStateLib for LimiterState global;

/// @author philogy <https://github.com/philogy>
library LimiterStateLib {
    uint256 internal constant _WAD_MASK = 0xffffffffffffffff;
    uint256 internal constant _TIME_MASK = 0xffffffff;

    uint256 internal constant _ELASTIC_OFFSET = 0;
    uint256 internal constant _MAIN_OFFSET = 64;
    uint256 internal constant _LAST_UPDATED_OFFSET = 224;

    error LimiterStatePackOverflow();

    function unpack(LimiterState state)
        internal
        pure
        returns (uint256 lastUpdated, uint256 mainBuffer, uint256 elasticBuffer)
    {
        uint256 packed = LimiterState.unwrap(state);
        lastUpdated = (packed >> _LAST_UPDATED_OFFSET) & _TIME_MASK;
        mainBuffer = (packed >> _MAIN_OFFSET) & _WAD_MASK;
        elasticBuffer = (packed >> _ELASTIC_OFFSET) & _WAD_MASK;
    }

    function pack(uint256 lastUpdated, uint256 mainBuffer, uint256 elasticBuffer)
        internal
        pure
        returns (LimiterState state)
    {
        if (mainBuffer > _WAD_MASK || elasticBuffer > _WAD_MASK) revert LimiterStatePackOverflow();
        // `lastUpdated` purposefully truncated
        state = LimiterState.wrap(
            lastUpdated << _LAST_UPDATED_OFFSET | mainBuffer << _MAIN_OFFSET | elasticBuffer << _ELASTIC_OFFSET
        );
    }
}
