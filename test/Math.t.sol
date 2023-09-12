// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Test} from "forge-std/Test.sol";
import {min, max, cappedSub, deltaAdd} from "src/utils/Math.sol";

/// @author philogy <https://github.com/philogy>
contract MathTest is Test {
    function setUp() public {}

    function test_fuzzingMax(uint256 x, uint256 y) public {
        if (x > y) {
            assertEq(max(x, y), x);
        } else {
            assertEq(max(x, y), y);
        }
        assertEq(max(x, y), max(y, x));
    }

    function test_fuzzingMin(uint256 x, uint256 y) public {
        if (x < y) {
            assertEq(min(x, y), x);
        } else {
            assertEq(min(x, y), y);
        }
        assertEq(min(x, y), min(y, x));
    }

    function test_fuzzingCappedSub(uint256 x, uint256 y) public {
        if (x < y) {
            assertEq(cappedSub(x, y), 0);
        } else {
            assertEq(cappedSub(x, y), x - y);
        }
    }

    function test_fuzzingDeltaAdd(uint256 x, int256 y) public {
        int256 unsafeRes;
        unchecked {
            unsafeRes = int256(x) + y;
        }

        if (int256(x) < 0 || unsafeRes < 0 || (y < 0 && uint256(unsafeRes) >= x) || (y > 0 && uint256(unsafeRes) <= x))
        {
            vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
            deltaAdd(x, y);
        } else {
            int256 res = int256(x) + y;
            assertGe(res, 0);

            assertEq(deltaAdd(x, y), uint256(res));
        }
    }
}
