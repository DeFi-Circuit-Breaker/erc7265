// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {LimiterConfig} from "./LimiterConfigLib.sol";
import {LimiterStateLib, LimiterState} from "./LimiterStateLib.sol";
import {delta} from "../utils/Timestamp.sol";
import {LimiterMathLib} from "./LimiterMathLib.sol";

type DecreaseLimiter is uint256;

using DecreaseLimiterLib for DecreaseLimiter global;

/// @author philogy <https://github.com/philogy>
library DecreaseLimiterLib {
    using FixedPointMathLib for uint256;

    error MainBufferAboveMax();
    error ElasticBufferAboveTVL();

    function _fromState(LimiterState state) internal pure returns (DecreaseLimiter limiter) {
        return DecreaseLimiter.wrap(LimiterState.unwrap(state));
    }

    function initNew(uint256 lastUpdatedAt, uint256 initialTvl, LimiterConfig config)
        internal
        pure
        returns (DecreaseLimiter limiter)
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
    ) internal pure returns (DecreaseLimiter) {
        return _fromState(
            LimiterStateLib.pack(
                lastUpdatedAt,
                mainBufferToRepr(mainBuffer, tvl, config),
                elasticBufferToRepr(elasticBuffer, tvl, config)
            )
        );
    }

    function getState(DecreaseLimiter limiter) internal pure returns (LimiterState state) {
        return LimiterState.wrap(DecreaseLimiter.unwrap(limiter));
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
        if (buffer > tvl) revert ElasticBufferAboveTVL();
        repr = tvl == 0 ? 0 : buffer.divWad(tvl);
    }

    function elasticBufferFromRepr(uint256 repr, uint256 tvl, LimiterConfig) internal pure returns (uint256 buffer) {
        buffer = tvl.mulWad(repr);
    }

    function applyInflow(DecreaseLimiter limiter, LimiterConfig config, uint256 preTvl, uint256 inflow)
        internal
        view
        returns (DecreaseLimiter updatedLimiter, uint256 overflow)
    {
        return applyInflow(limiter, config, preTvl, inflow, block.timestamp);
    }

    function applyInflow(
        DecreaseLimiter limiter,
        LimiterConfig config,
        uint256 preTvl,
        uint256 inflow,
        uint256 currentTime
    ) internal pure returns (DecreaseLimiter updatedLimiter, uint256 overflow) {
        (uint256 mainBuffer, uint256 elasticBuffer) = _getPassivelyUpdatedBuffers(limiter, config, preTvl, currentTime);
        // Calculate active buffer updates.
        elasticBuffer += inflow;
        // Prepare and return results
        uint256 newTvl = preTvl + inflow;
        updatedLimiter = initNew({
            lastUpdatedAt: currentTime,
            mainBuffer: mainBuffer,
            elasticBuffer: elasticBuffer,
            tvl: newTvl,
            config: config
        });
        // Inflow cannot overflow/block a *decrease* limiter, upwards direction uncapped. Kept for
        // the sake of consistency.
        overflow = 0;
    }

    function applyOutflow(DecreaseLimiter limiter, LimiterConfig config, uint256 preTvl, uint256 outflow)
        internal
        view
        returns (DecreaseLimiter updatedLimiter, uint256 overflow)
    {
        return applyInflow(limiter, config, preTvl, outflow, block.timestamp);
    }

    function applyOutflow(
        DecreaseLimiter limiter,
        LimiterConfig config,
        uint256 preTvl,
        uint256 outflow,
        uint256 currentTime
    ) internal pure returns (DecreaseLimiter updatedLimiter, uint256 overflow) {
        (uint256 mainBuffer, uint256 elasticBuffer) = _getPassivelyUpdatedBuffers(limiter, config, preTvl, currentTime);
        // Calculate active buffer updates.
        (mainBuffer, elasticBuffer, overflow) =
            LimiterMathLib.depleteBuffers({mainBuffer: mainBuffer, elasticBuffer: elasticBuffer, amount: outflow});
        // Repack into new limiter.
        uint256 newTvl = preTvl - outflow;
        updatedLimiter = initNew({
            lastUpdatedAt: currentTime,
            mainBuffer: mainBuffer,
            elasticBuffer: elasticBuffer,
            tvl: newTvl,
            config: config
        });
    }

    function applyUpdate(DecreaseLimiter limiter, LimiterConfig config, uint256 tvl)
        internal
        view
        returns (DecreaseLimiter updatedLimiter)
    {
        return applyUpdate(limiter, config, tvl, block.timestamp);
    }

    function applyUpdate(DecreaseLimiter limiter, LimiterConfig config, uint256 tvl, uint256 currentTime)
        internal
        pure
        returns (DecreaseLimiter updatedLimiter)
    {
        (uint256 mainBuffer, uint256 elasticBuffer) = _getPassivelyUpdatedBuffers(limiter, config, tvl, currentTime);
        // Repack into new limiter.
        updatedLimiter = initNew({
            lastUpdatedAt: currentTime,
            mainBuffer: mainBuffer,
            elasticBuffer: elasticBuffer,
            tvl: tvl,
            config: config
        });
    }

    function _getPassivelyUpdatedBuffers(
        DecreaseLimiter limiter,
        LimiterConfig config,
        uint256 tvl,
        uint256 currentTime
    ) internal pure returns (uint256 mainBuffer, uint256 elasticBuffer) {
        // Unpack & decode values.
        (uint256 lastUpdatedAt, uint256 mainBufferRepr, uint256 elasticBufferRepr) = limiter.getState().unpack();
        mainBuffer = mainBufferFromRepr(mainBufferRepr, tvl, config);
        elasticBuffer = elasticBufferFromRepr(elasticBufferRepr, tvl, config);
        uint256 dt = delta(currentTime, lastUpdatedAt);
        (uint256 maxDrawdownWad, uint256 mainReplenishWindow, uint256 elasticDecayWindow) = config.unpack();
        // Calculate passive buffer updates.
        mainBuffer = LimiterMathLib.replenishMainBuffer({
            buffer: mainBuffer,
            bufferCap: tvl.mulWad(maxDrawdownWad),
            dt: dt,
            replenishWindow: mainReplenishWindow
        });
        elasticBuffer = LimiterMathLib.decayElasticBuffer({
            elasticBuffer: elasticBuffer,
            dt: dt,
            decayWindow: elasticDecayWindow
        });
    }
}
