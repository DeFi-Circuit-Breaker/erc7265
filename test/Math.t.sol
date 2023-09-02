// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Test} from "forge-std/Test.sol";
import {min, max, cappedSub} from "src/utils/Math.sol";

/// @author philogy <https://github.com/philogy>
contract MathTest is Test {
    function setUp() public {}

    function test_fuzzingMax(uint256 x, uint256 y) public {
        if (x > y) {
            assertEq(max(x, y), x);
        } else {
            assertEq(max(x, y), y);
        }
    }

    function test_fuzzingMin(uint256 x, uint256 y) public {
        if (x < y) {
            assertEq(min(x, y), x);
        } else {
            assertEq(min(x, y), y);
        }
    }

    function test_fuzzingCappedSub(uint256 x, uint256 y) public {
        if (x < y) {
            assertEq(cappedSub(x, y), 0);
        } else {
            assertEq(cappedSub(x, y), x - y);
        }
    }
}
