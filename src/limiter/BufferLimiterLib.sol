// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {cappedSub, min} from "../utils/Math.sol";
import {console2 as console} from "forge-std/console2.sol";

struct Buffer {
    uint256 lastUpdatedAt;
    uint256 mainUsedWad;
    uint256 elasticBufferWad;
}

using BufferLib for Buffer global;

/// @author philogy <https://github.com/philogy>
library BufferLib {
    uint256 internal constant WAD = 1e18;

    function update(Buffer storage self, uint256 mainWindow, uint256 elasticWindow, uint256 time) internal {
        uint256 delta = time - self.lastUpdatedAt;

        self.mainUsedWad = cappedSub(self.mainUsedWad, delta * WAD / mainWindow);

        uint256 elasticBuffer = self.elasticBufferWad;
        self.elasticBufferWad = cappedSub(elasticBuffer, elasticBuffer * delta / elasticWindow);

        self.lastUpdatedAt = time;
    }

    /**
     * @dev TODO: Investigate how `preTvl` can be manipulate when balance is increased over time (e.g.
     * via silent ERC20 transfers) without actually updating.
     */
    function recordInflow(
        Buffer storage self,
        uint256 mainWindow,
        uint256 elasticWindow,
        uint256 time,
        uint256 preTvl,
        uint256 amount
    ) internal {
        uint256 delta = time - self.lastUpdatedAt;
        uint256 newTvl = preTvl + amount;

        uint256 unadjUsed = cappedSub(self.mainUsedWad, delta * WAD / mainWindow);
        self.mainUsedWad = unadjUsed * preTvl / newTvl;

        uint256 elasticBuffer = self.elasticBufferWad;
        uint256 unadjElastic = cappedSub(elasticBuffer, elasticBuffer * delta / elasticWindow);
        self.elasticBufferWad = (unadjElastic * preTvl + amount * WAD) / newTvl;

        self.lastUpdatedAt = time;
    }

    function recordOutflow(
        Buffer storage self,
        uint256 maxDrawWad,
        uint256 mainWindow,
        uint256 elasticWindow,
        uint256 time,
        uint256 preTvl,
        uint256 amount
    ) internal returns (bool) {
        uint256 delta = time - self.lastUpdatedAt;
        uint256 newTvl = preTvl - amount;

        uint256 mainUsedWad = cappedSub(self.mainUsedWad, delta * WAD / mainWindow);

        uint256 elasticBuffer = self.elasticBufferWad;
        uint256 elasticWad = cappedSub(elasticBuffer, elasticBuffer * delta / elasticWindow);

        uint256 useWad = amount * WAD / preTvl;

        if (useWad > elasticWad) {
            unchecked {
                useWad -= elasticWad;
            }
            elasticWad = 0;
        } else {
            unchecked {
                elasticWad -= useWad;
            }
            useWad = 0;
        }
        mainUsedWad += min(useWad * WAD / maxDrawWad, WAD);

        // Max drawdown exceeded, skip updates and return `false`.
        if (mainUsedWad > WAD) return false;

        self.mainUsedWad = mainUsedWad * preTvl / newTvl;
        self.elasticBufferWad = elasticWad * preTvl / newTvl;
        self.lastUpdatedAt = time;

        return true;
    }
}
