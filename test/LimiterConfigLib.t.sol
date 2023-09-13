// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {LimiterConfigLib, LimiterConfig} from "src/limiter/LimiterConfigLib.sol";
import {Test} from "forge-std/Test.sol";
import {console2 as console} from "forge-std/console2.sol";

/// @author philogy <https://github.com/philogy>
contract LimiterConfigLibTest is Test {
    function test_fuzzingConfigCreation(uint256 maxDrawWad, uint256 mainWindow, uint256 elasticWindow) public {
        if (maxDrawWad == 0 || maxDrawWad >= 1e18 || mainWindow > type(uint32).max || elasticWindow > type(uint32).max)
        {
            vm.expectRevert(LimiterConfigLib.InvalidConfig.selector);
            LimiterConfigLib.initNew(maxDrawWad, mainWindow, elasticWindow);
        } else {
            LimiterConfig config = LimiterConfigLib.initNew(maxDrawWad, mainWindow, elasticWindow);
            assertEq(
                LimiterConfig.unwrap(config),
                uint128(bytes16(abi.encodePacked(uint32(elasticWindow), uint32(mainWindow), uint64(maxDrawWad)))),
                "unexpected packing"
            );
            (uint256 outMaxDrawWad, uint256 outMainWindow, uint256 outElasticWindow) = config.unpack();
            assertEq(maxDrawWad, outMaxDrawWad, "maxDrawWad mismatch");
            assertEq(mainWindow, outMainWindow, "mainWindow mismatch");
            assertEq(elasticWindow, outElasticWindow, "elasticWindow mismatch");
        }
    }
}
