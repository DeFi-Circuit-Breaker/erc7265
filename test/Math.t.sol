// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Test} from "forge-std/Test.sol";
import {min, max, cappedSub, deltaAdd, abs, sign, signNeg} from "src/utils/Math.sol";

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
        uint256 absY;

        if (y == type(int256).min) {
            absY = uint256(y);
        } else if (y < 0) {
            absY = uint256(-y);
        } else {
            absY = uint256(y);
        }

        if ((y < 0 && absY > x) || (y > 0 && absY > type(uint256).max - x)) {
            vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
            deltaAdd(x, y);
        } else {
            uint256 res = y < 0 ? x - absY : x + absY;
            assertEq(deltaAdd(x, y), res);
        }
    }

    function test_fuzzingAbs(int256 x) public {
        unchecked {
            assertEq(abs(x), x < 0 ? uint256(-x) : uint256(x));
        }
    }

    function test_fuzzingSign(int256 x) public {
        assertEq(x < 0 ? int256(-1) : int256(1), sign(x));
    }

    function test_fuzzingSignNeg(int256 x) public {
        assertEq(x < 0 ? int256(1) : int256(-1), signNeg(x));
    }
}
