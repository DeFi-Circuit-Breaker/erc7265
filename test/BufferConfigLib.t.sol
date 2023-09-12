// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {BufferConfigLib, BufferConfig} from "src/limiter/BufferConfigLib.sol";
import {Test} from "forge-std/Test.sol";
import {console2 as console} from "forge-std/console2.sol";

/// @author philogy <https://github.com/philogy>
contract BuffConfigLibTest is Test {
    function test_fuzzingConfigCreation(int256 maxDrawWad, uint256 mainWindow, uint256 elasticWindow) public {
        if (
            maxDrawWad == 0 || maxDrawWad >= int256(1e18) || maxDrawWad <= int256(-1e18)
                || mainWindow > type(uint32).max || elasticWindow > type(uint32).max
        ) {
            vm.expectRevert(BufferConfigLib.InvalidConfig.selector);
            BufferConfigLib.initNew(maxDrawWad, mainWindow, elasticWindow);
        } else {
            BufferConfig config = BufferConfigLib.initNew(maxDrawWad, mainWindow, elasticWindow);
            assertEq(
                BufferConfig.unwrap(config),
                uint128(bytes16(abi.encodePacked(uint32(elasticWindow), uint32(mainWindow), int64(maxDrawWad)))),
                "unexpected packing"
            );
            (int256 outMaxDrawWad, uint256 outMainWindow, uint256 outElasticWindow) = config.unpack();
            assertEq(maxDrawWad, outMaxDrawWad, "maxDrawWad mismatch");
            assertEq(mainWindow, outMainWindow, "mainWindow mismatch");
            assertEq(elasticWindow, outElasticWindow, "elasticWindow mismatch");
        }
    }
}
