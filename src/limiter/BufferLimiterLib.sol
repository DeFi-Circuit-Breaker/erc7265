// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SafeCastLib} from "solady/utils/SafeCastLib.sol";
import {cappedSub} from "./Math.sol";

struct Buffer {
    uint256 lastUpdatedAt;
    uint256 used;
    uint256 above;
}

using BufferLib for Buffer global;

/// @author philogy <https://github.com/philogy>
library BufferLib {
    using SafeCastLib for uint256;

    uint256 internal constant BPS = 1e4;

    function recordInflow(
        Buffer storage self,
        uint256 maxDrawDownBps,
        uint256 window,
        uint256 time,
        uint256 preTvl,
        uint256 amount
    ) internal {
        uint256 delta = time - self.lastUpdatedAt;
        self.used = self.used.cappedSub(preTvl * maxDrawDownBps * delta / window / BPS);
        uint256 above = self.above;
        self.above = above.cappedSub(above * delta / window) + amount;
        self.lastUpdatedAt = time;
    }

    function recordOutflow(
        Buffer storage self,
        uint256 maxDrawDownBps,
        uint256 window,
        uint256 time,
        uint256 preTvl,
        uint256 amount
    ) internal returns (bool) {
        uint256 delta = time - self.lastUpdatedAt;
        uint256 above = self.above;
        above = above.cappedSub(above * delta / window);
        uint256 cap = preTvl * maxDrawDownBps / BPS + above;
        uint256 newUsed = self.used.cappedSub(preTvl * maxDrawDownBps * delta / window / BPS) + amount;
        if (newUsed > cap) return false;
        self.used = newUsed;
        self.above = above;
        self.lastUpdatedAt = time;
        return true;
    }
}
