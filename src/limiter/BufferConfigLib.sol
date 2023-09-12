// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {abs} from "src/utils/Math.sol";

type BufferConfig is uint128;

using BufferConfigLib for BufferConfig global;

/// @author philogy <https://github.com/philogy>
library BufferConfigLib {
    int256 internal constant _MAX_DRAW_BOUND_UPPER = 1e18;
    int256 internal constant _MAX_DRAW_BOUND_LOWER = -1e18;
    uint256 internal constant _MAX_WINDOW_BOUND = 0x100000000;

    uint256 internal constant _MAX_DRAW_SIGNEXTEND_BYTES = 7; // 8 - 1
    uint256 internal constant _MAX_DRAW_MASK = 0xffffffffffffffff;
    uint256 internal constant _WINDOW_MASK = 0xffffffff;
    uint256 internal constant _MAIN_WINDOW_OFFSET = 64;
    uint256 internal constant _ELASTIC_WINDOW_OFFSET = 96;

    error InvalidConfig();

    uint256 internal constant _INVALID_CONFIG_ERROR_SELECTOR = 0x35be3ac8;

    function initNew(int256 maxDrawWad, uint256 mainWindow, uint256 elasticWindow)
        internal
        pure
        returns (BufferConfig config)
    {
        assembly {
            // Prevent `maxDrawWad` from being out-of-bounds or zero and ensure windows fit in 32-bits.
            if iszero(
                and(
                    and(sgt(maxDrawWad, _MAX_DRAW_BOUND_LOWER), slt(maxDrawWad, _MAX_DRAW_BOUND_UPPER)),
                    and(gt(maxDrawWad, 0), lt(or(mainWindow, elasticWindow), _MAX_WINDOW_BOUND))
                )
            ) {
                mstore(0x00, _INVALID_CONFIG_ERROR_SELECTOR)
                revert(0x1c, 0x04)
            }
            config :=
                or(
                    and(maxDrawWad, _MAX_DRAW_MASK),
                    or(shl(_MAIN_WINDOW_OFFSET, mainWindow), shl(_ELASTIC_WINDOW_OFFSET, elasticWindow))
                )
        }
    }

    function unpack(BufferConfig config)
        internal
        pure
        returns (int256 maxDrawWad, uint256 mainWindow, uint256 elasticWindow)
    {
        maxDrawWad = config.getMaxDrawWad();
        mainWindow = config.getMainWindow();
        elasticWindow = config.getElasticWindow();
    }

    function getMaxDrawWad(BufferConfig config) internal pure returns (int256 maxDrawWad) {
        assembly {
            // Don't need to mask `config` because `signextend` ignores bytes outside of `b+1`.
            maxDrawWad := signextend(_MAX_DRAW_SIGNEXTEND_BYTES, config)
        }
    }

    function getMainWindow(BufferConfig config) internal pure returns (uint256 mainWindow) {
        assembly {
            mainWindow := and(shr(_MAIN_WINDOW_OFFSET, config), _WINDOW_MASK)
        }
    }

    function getElasticWindow(BufferConfig config) internal pure returns (uint256 elasticWindow) {
        assembly {
            elasticWindow := and(shr(_ELASTIC_WINDOW_OFFSET, config), _WINDOW_MASK)
        }
    }
}
