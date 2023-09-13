// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SafeCastLib} from "solady/utils/SafeCastLib.sol";
import {LimiterConfig} from "./LimiterConfigLib.sol";
import {cappedSub, abs, deltaAdd, min} from "../utils/Math.sol";
import {delta} from "../utils/Timestamp.sol";

/**
 * @dev Packed active limiter state (
 *   uint32: lastUpdated,
 *   bool(uint1): isError,
 *   uint72: relMainBuffer,
 *   uint151: relElastic
 * )
 */
type DecreaseResult is uint256;

type DecreaseLimiter is uint256;

using DecreaseLimiterLib for DecreaseLimiter global;
using DecreaseLimiterLib for DecreaseResult global;

/// @author philogy <https://github.com/philogy>
library DecreaseLimiterLib {
    using SafeCastLib for uint256;
    using SafeCastLib for int256;

    uint256 internal constant WAD = 1e18;
    int256 internal constant SWAD = 1e18;

    uint256 internal constant _ELASTIC_BUFFER_OFFSET = 0;
    uint256 internal constant _MAIN_BUFFER_OFFSET = 151;
    uint256 internal constant _OVERFLOWED_OFFSET = 223;
    uint256 internal constant _TIMESTAMP_OFFSET = 224;
    uint256 internal constant _TIMESTAMP_MASK = 0xffffffff;

    uint256 internal constant _BUFFER_IS_ERROR_FLAG = 0x80000000000000000000000000000000000000000000000000000000;
    uint256 internal constant _BOUND_MAIN_USED_WAD = 0x1000000000000000000;
    uint256 internal constant _BOUND_ELASTIC_BUFFER_WAD = 0x80000000000000000000000000000000000000;

    error BufferPropertyOverflow();
    error UnwrapBufferResultErr();
    error UnwrapBufferResultOk();

    /// @dev Selector of `BufferPropertyOverflow()`.
    uint256 internal constant _BUFFER_PROPERTY_OVERFLOW_ERROR_SELECTOR = 0x5f39d474;

    /// @dev Selector of `UnwrapBufferResultErr()`.
    uint256 internal constant _UNWRAP_BUFFER_ERR_ERROR_SELECTOR = 0xfb6fddf2;

    /// @dev Selector of `UnwrapBufferResultOk()`.
    uint256 internal constant _UNWRAP_BUFFER_OK_ERROR_SELECTOR = 0xce3029e3;

    /**
     * @dev Initializes a new limiter, equivalent to `_setBuffer(lastUpdatedAt, WAD, 0)`.
     */
    function initNew(uint256 lastUpdatedAt) internal pure returns (DecreaseLimiter limiter) {
        assembly {
            limiter := or(shl(_TIMESTAMP_OFFSET, lastUpdatedAt), shl(_MAIN_BUFFER_OFFSET, WAD))
        }
    }

    function recordFlow(DecreaseLimiter limiter, LimiterConfig config, uint256 preReserves, int256 flow)
        internal
        view
        returns (DecreaseResult)
    {
        return limiter.recordFlow({config: config, time: block.timestamp, preReserves: preReserves, flow: flow});
    }

    function recordFlow(DecreaseLimiter limiter, LimiterConfig config, uint256 time, uint256 preReserves, int256 flow)
        internal
        pure
        returns (DecreaseResult)
    {
        (uint256 maxDrawWad, uint256 mainWindow, uint256 elasticWindow) = config.unpack();
        return limiter._recordFlow({
            maxDrawWad: maxDrawWad,
            mainWindow: mainWindow,
            elasticWindow: elasticWindow,
            time: time,
            preReserves: preReserves,
            flow: flow
        });
    }

    function update(DecreaseLimiter limiter, LimiterConfig config) internal view returns (DecreaseLimiter) {
        return limiter.update(config, block.timestamp);
    }

    function update(DecreaseLimiter limiter, LimiterConfig config, uint256 time)
        internal
        pure
        returns (DecreaseLimiter)
    {
        (uint256 relMainBuffer, uint256 relElastic) = limiter._getUpdated({
            mainWindow: config.getMainWindow(),
            elasticWindow: config.getElasticWindow(),
            time: time
        });
        return _setBuffer({lastUpdatedAt: time, relMainBuffer: relMainBuffer, relElastic: relElastic});
    }

    function unpack(DecreaseLimiter limiter)
        internal
        pure
        returns (uint256 lastUpdatedAt, uint256 relMainBuffer, uint256 relElastic)
    {
        assembly {
            lastUpdatedAt := shr(_TIMESTAMP_OFFSET, limiter)
            relMainBuffer := and(shr(_MAIN_BUFFER_OFFSET, limiter), sub(_BOUND_MAIN_USED_WAD, 1))
            relElastic := and(shr(_ELASTIC_BUFFER_OFFSET, limiter), sub(_BOUND_ELASTIC_BUFFER_WAD, 1))
        }
    }

    function getMaxFlow(DecreaseLimiter buffer, LimiterConfig config, uint256 currentReserves)
        internal
        pure
        returns (uint256 maxMainFlow, uint256 maxElasticDeplete)
    {
        return buffer._getMaxFlow(config.getMaxDrawWad(), currentReserves);
    }

    function _recordFlow(
        DecreaseLimiter buffer,
        uint256 maxDrawWad,
        uint256 mainWindow,
        uint256 elasticWindow,
        uint256 time,
        uint256 preReserves,
        int256 flow
    ) internal pure returns (DecreaseResult) {
        (uint256 relMainBuffer, uint256 relElastic) =
            buffer._getUpdated({mainWindow: mainWindow, elasticWindow: elasticWindow, time: time});

        uint256 elasticBufferWad = relElastic * preReserves;
        uint256 changeWad = abs(flow) * WAD;
        uint256 newReserves = deltaAdd(preReserves, flow);

        // The limiter can either be replenished or temporarily expanded. The decrease limiter is
        // depleted when the
        // flow is in the limited direction i.e. the sign of the `maxDrawWad` parameter and `flow`
        // are the same.
        if (flow < 0) {
            // Deplete elastic buffer first.
            unchecked {
                (changeWad, elasticBufferWad) = changeWad > elasticBufferWad
                    ? (changeWad - elasticBufferWad, uint256(0))
                    : (uint256(0), elasticBufferWad - changeWad);
            }

            // Compute main buffer update components (v * x; dx / r).
            uint256 mainBufferWad = relMainBuffer * preReserves;
            uint256 bufferChange = changeWad * WAD / maxDrawWad;

            // Check whether limit was exceeded (if so it means both buffers were depleted => 0).
            if (bufferChange > mainBufferWad) {
                return Err(_setBuffer({lastUpdatedAt: time, relMainBuffer: 0, relElastic: 0}));
            } else {
                // Otherwise finalize the computation and return the buffer.
                unchecked {
                    mainBufferWad -= bufferChange;
                }
                return Ok(
                    _setBuffer({
                        lastUpdatedAt: time,
                        relMainBuffer: mainBufferWad / newReserves,
                        relElastic: elasticBufferWad / newReserves
                    })
                );
            }
        } else {
            // Adds to elastic buffer, this ensures that short-term liquidity changes can cancel each
            // other out with limited impact on the main buffer. Mitigates DoS but also leaves newer
            // flows vulnerable. Large legitimate inflows, such as large deposits should therefore
            // be done in chunks over time to avoid having too much vulnerable at one time.
            elasticBufferWad += changeWad;
            return Ok(
                _setBuffer({
                    lastUpdatedAt: time,
                    relMainBuffer: relMainBuffer * preReserves / newReserves,
                    relElastic: elasticBufferWad / newReserves
                })
            );
        }
    }

    function _getMaxFlow(DecreaseLimiter limiter, uint256 maxDrawWad, uint256 currentReserves)
        internal
        pure
        returns (uint256 maxMainFlow, uint256 maxElasticDeplete)
    {
        (, uint256 relMainBuffer, uint256 relElastic) = limiter.unpack();
        maxMainFlow = relMainBuffer * currentReserves * maxDrawWad / WAD / WAD;
        maxElasticDeplete = relElastic * currentReserves / WAD;
    }

    function _getUpdated(DecreaseLimiter limiter, uint256 mainWindow, uint256 elasticWindow, uint256 time)
        internal
        pure
        returns (uint256 relMainBuffer, uint256 relElastic)
    {
        uint256 lastUpdatedAt;
        (lastUpdatedAt, relMainBuffer, relElastic) = limiter.unpack();
        uint256 dt = delta(time, lastUpdatedAt);

        relMainBuffer = min(relMainBuffer + dt * WAD / mainWindow, WAD);
        relElastic = cappedSub(relElastic, relElastic * dt / elasticWindow);
    }

    function _setBuffer(uint256 lastUpdatedAt, uint256 relMainBuffer, uint256 relElastic)
        private
        pure
        returns (DecreaseLimiter limiter)
    {
        assembly {
            if iszero(and(lt(relMainBuffer, _BOUND_MAIN_USED_WAD), lt(relElastic, _BOUND_ELASTIC_BUFFER_WAD))) {
                mstore(0x00, _BUFFER_PROPERTY_OVERFLOW_ERROR_SELECTOR)
                revert(0x1c, 0x04)
            }
            // Purposefully truncate `lastUpdatedAt`.
            limiter :=
                or(
                    shl(_TIMESTAMP_OFFSET, lastUpdatedAt),
                    or(shl(_MAIN_BUFFER_OFFSET, relMainBuffer), shl(_ELASTIC_BUFFER_OFFSET, relElastic))
                )
        }
    }

    ////////////////////////////////////////////////////////////////
    //                   LIMITER RESULT HELPERS                   //
    ////////////////////////////////////////////////////////////////

    function Ok(DecreaseLimiter limiter) internal pure returns (DecreaseResult result) {
        assembly {
            result := limiter
        }
    }

    function Err(DecreaseLimiter limiter) internal pure returns (DecreaseResult result) {
        assembly {
            result := or(limiter, _BUFFER_IS_ERROR_FLAG)
        }
    }

    function isOk(DecreaseResult result) internal pure returns (bool ok) {
        assembly {
            ok := iszero(and(result, _BUFFER_IS_ERROR_FLAG))
        }
    }

    function isErr(DecreaseResult result) internal pure returns (bool errored) {
        assembly {
            errored := and(result, _BUFFER_IS_ERROR_FLAG)
        }
    }

    /**
     * @dev Unwraps a successful `DecreaseResult` type into a `DecreaseLimiter`. Reverts if result is an error
     * (has error flag set).
     */
    function unwrap(DecreaseResult result) internal pure returns (DecreaseLimiter limiter) {
        assembly {
            if and(result, _BUFFER_IS_ERROR_FLAG) {
                mstore(0x00, _UNWRAP_BUFFER_ERR_ERROR_SELECTOR)
                revert(0x1c, 0x04)
            }
            limiter := result
        }
    }

    /**
     * @dev Unwraps an errored `DecreaseResult` type into a `DecreaseLimiter`. Reverts if result has no error
     * (error flag not set).
     */
    function unwrapErr(DecreaseResult result) internal pure returns (DecreaseLimiter limiter) {
        assembly {
            if iszero(and(result, _BUFFER_IS_ERROR_FLAG)) {
                mstore(0x00, _UNWRAP_BUFFER_OK_ERROR_SELECTOR)
                revert(0x1c, 0x04)
            }
            // Clear error flag.
            limiter := and(result, not(_BUFFER_IS_ERROR_FLAG))
        }
    }
}
