// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {cappedSub, abs, deltaAdd, min} from "../utils/Math.sol";
import {SafeCastLib} from "solady/utils/SafeCastLib.sol";

/**
 * @dev Packed active buffer state (
 *   uint32: lastUpdated,
 *   bool(uint1): isError,
 *   uint72: relMainBuffer,
 *   uint151: relElastic
 * )
 */
type BufferResult is uint256;

type Buffer is uint256;

using BufferLib for Buffer global;
using BufferLib for BufferResult global;

/// @author philogy <https://github.com/philogy>
library BufferLib {
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
    error UnwrapBufferResultError();

    /// @dev Selector of `BufferPropertyOverflow()`.
    uint256 internal constant _BUFFER_PROPERTY_OVERFLOW_ERROR_SELECTOR = 0x5f39d474;

    /// @dev Selector of `UnwrapBufferResultError()`.
    uint256 internal constant _UNWRAP_BUFFER_ERROR_SELECTOR = 0xca428dba;

    function recordFlow(
        Buffer buffer,
        int256 maxDrawWad,
        uint256 mainWindow,
        uint256 elasticWindow,
        uint256 time,
        uint256 reserves,
        int256 flow
    ) internal pure returns (BufferResult) {
        (uint256 relMainBuffer, uint256 relElastic) =
            buffer.getUpdated({mainWindow: mainWindow, elasticWindow: elasticWindow, time: time});

        uint256 elasticBufferWad = relElastic * reserves;
        uint256 changeWad = abs(flow) * WAD;
        uint256 newReserves = deltaAdd(reserves, flow);

        if ((flow < 0) == (maxDrawWad < 0)) {
            // Deplete elastic buffer first
            unchecked {
                (changeWad, elasticBufferWad) = changeWad > elasticBufferWad
                    ? (changeWad - elasticBufferWad, uint256(0))
                    : (uint256(0), elasticBufferWad - changeWad);
            }

            uint256 mainBuffer = relMainBuffer * reserves;
            uint256 bufferChange = changeWad * WAD / abs(maxDrawWad);

            if (bufferChange > mainBuffer) {
                return Err(_setBuffer({lastUpdatedAt: time, relMainBuffer: 0, relElastic: 0}));
            } else {
                unchecked {
                    mainBuffer -= bufferChange;
                }
                return Ok(
                    _setBuffer({
                        lastUpdatedAt: time,
                        relMainBuffer: mainBuffer / newReserves,
                        relElastic: elasticBufferWad / newReserves
                    })
                );
            }
        } else {
            elasticBufferWad += changeWad;
            // Buffer elastic replenish
            return Ok(
                _setBuffer({
                    lastUpdatedAt: time,
                    relMainBuffer: relMainBuffer * reserves / newReserves,
                    relElastic: elasticBufferWad / newReserves
                })
            );
        }
    }

    function update(Buffer buffer, uint256 mainWindow, uint256 elasticWindow, uint256 time)
        internal
        pure
        returns (Buffer)
    {
        (uint256 relMainBuffer, uint256 relElastic) =
            buffer.getUpdated({mainWindow: mainWindow, elasticWindow: elasticWindow, time: time});
        return _setBuffer({lastUpdatedAt: time, relMainBuffer: relMainBuffer, relElastic: relElastic});
    }

    function getMaxFlow(Buffer buffer, int256 maxDrawWad, uint256 reserves)
        internal
        pure
        returns (int256 maxMainFlow, uint256 maxElasticDeplete)
    {
        (, uint256 relMainBuffer, uint256 relElastic) = buffer.unpack();
        maxMainFlow = (relMainBuffer * reserves).toInt256() * maxDrawWad / SWAD / SWAD;
        maxElasticDeplete = relElastic * reserves / WAD;
    }

    function getUpdated(Buffer buffer, uint256 mainWindow, uint256 elasticWindow, uint256 time)
        internal
        pure
        returns (uint256 relMainBuffer, uint256 relElastic)
    {
        uint256 lastUpdatedAt;
        (lastUpdatedAt, relMainBuffer, relElastic) = buffer.unpack();
        uint256 delta = _delta(time, lastUpdatedAt);

        relMainBuffer = min(relMainBuffer + delta * WAD / mainWindow, WAD);
        relElastic = cappedSub(relElastic, relElastic * delta / elasticWindow);
    }

    /**
     * @dev Initializes a new buffer, equivalent to `_setBuffer(lastUpdatedAt, WAD, 0)`.
     */
    function newBuffer(uint256 lastUpdatedAt) internal pure returns (Buffer buffer) {
        assembly {
            buffer := or(shl(_TIMESTAMP_OFFSET, lastUpdatedAt), shl(_MAIN_BUFFER_OFFSET, WAD))
        }
    }

    function _setBuffer(uint256 lastUpdatedAt, uint256 relMainBuffer, uint256 relElastic)
        private
        pure
        returns (Buffer buffer)
    {
        assembly {
            if iszero(and(lt(relMainBuffer, _BOUND_MAIN_USED_WAD), lt(relElastic, _BOUND_ELASTIC_BUFFER_WAD))) {
                mstore(0x00, _BUFFER_PROPERTY_OVERFLOW_ERROR_SELECTOR)
                revert(0x1c, 0x04)
            }
            // Purposefully truncate `lastUpdatedAt`.
            buffer :=
                or(
                    shl(_TIMESTAMP_OFFSET, lastUpdatedAt),
                    or(shl(_MAIN_BUFFER_OFFSET, relMainBuffer), shl(_ELASTIC_BUFFER_OFFSET, relElastic))
                )
        }
    }

    function unpack(Buffer buffer)
        internal
        pure
        returns (uint256 lastUpdatedAt, uint256 relMainBuffer, uint256 relElastic)
    {
        assembly {
            lastUpdatedAt := shr(_TIMESTAMP_OFFSET, buffer)
            relMainBuffer := and(shr(_MAIN_BUFFER_OFFSET, buffer), sub(_BOUND_MAIN_USED_WAD, 1))
            relElastic := and(shr(_ELASTIC_BUFFER_OFFSET, buffer), sub(_BOUND_ELASTIC_BUFFER_WAD, 1))
        }
    }

    function Ok(Buffer buffer) internal pure returns (BufferResult result) {
        assembly {
            result := buffer
        }
    }

    function Err(Buffer buffer) internal pure returns (BufferResult result) {
        assembly {
            result := or(buffer, _BUFFER_IS_ERROR_FLAG)
        }
    }

    function isErr(BufferResult result) internal pure returns (bool errored) {
        assembly {
            errored := and(result, _BUFFER_IS_ERROR_FLAG)
        }
    }

    function unwrap(BufferResult result) internal pure returns (Buffer buffer) {
        assembly {
            if and(result, _BUFFER_IS_ERROR_FLAG) {
                mstore(0x00, _UNWRAP_BUFFER_ERROR_SELECTOR)
                revert(0x1c, 0x04)
            }
            buffer := result
        }
    }

    function _delta(uint256 time, uint256 lastUpdatedAt) internal pure returns (uint256 delta) {
        assembly {
            delta := and(_TIMESTAMP_MASK, sub(time, lastUpdatedAt))
        }
    }
}
