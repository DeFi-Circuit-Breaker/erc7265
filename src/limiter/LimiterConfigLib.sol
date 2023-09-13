// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

type LimiterConfig is uint128;

using LimiterConfigLib for LimiterConfig global;

/// @author philogy <https://github.com/philogy>
library LimiterConfigLib {
    uint256 internal constant _MAX_DRAW_BOUND_SUB_1 = 999999999999999999;
    uint256 internal constant _MAX_WINDOW_BOUND = 0x100000000;

    uint256 internal constant _MAX_DRAW_MASK = 0xffffffffffffffff;
    uint256 internal constant _WINDOW_MASK = 0xffffffff;
    uint256 internal constant _MAIN_WINDOW_OFFSET = 64;
    uint256 internal constant _ELASTIC_WINDOW_OFFSET = 96;

    error InvalidConfig();

    /// @dev Selector of `InvalidConfig()`.
    uint256 internal constant _INVALID_CONFIG_ERROR_SELECTOR = 0x35be3ac8;

    function initNew(uint256 maxDrawWad, uint256 mainWindow, uint256 elasticWindow)
        internal
        pure
        returns (LimiterConfig config)
    {
        assembly {
            // Prevent `maxDrawWad` from being out-of-bounds or zero and ensure windows fit in 32-bits.
            if iszero(
                and(lt(sub(maxDrawWad, 1), _MAX_DRAW_BOUND_SUB_1), lt(or(mainWindow, elasticWindow), _MAX_WINDOW_BOUND))
            ) {
                mstore(0x00, _INVALID_CONFIG_ERROR_SELECTOR)
                revert(0x1c, 0x04)
            }
            config :=
                or(maxDrawWad, or(shl(_MAIN_WINDOW_OFFSET, mainWindow), shl(_ELASTIC_WINDOW_OFFSET, elasticWindow)))
        }
    }

    function unpack(LimiterConfig config)
        internal
        pure
        returns (uint256 maxDrawWad, uint256 mainWindow, uint256 elasticWindow)
    {
        maxDrawWad = config.getMaxDrawWad();
        mainWindow = config.getMainWindow();
        elasticWindow = config.getElasticWindow();
    }

    function getMaxDrawWad(LimiterConfig config) internal pure returns (uint256 maxDrawWad) {
        assembly {
            maxDrawWad := and(_MAX_DRAW_MASK, config)
        }
    }

    function getMainWindow(LimiterConfig config) internal pure returns (uint256 mainWindow) {
        assembly {
            mainWindow := and(shr(_MAIN_WINDOW_OFFSET, config), _WINDOW_MASK)
        }
    }

    function getElasticWindow(LimiterConfig config) internal pure returns (uint256 elasticWindow) {
        assembly {
            elasticWindow := and(shr(_ELASTIC_WINDOW_OFFSET, config), _WINDOW_MASK)
        }
    }
}
