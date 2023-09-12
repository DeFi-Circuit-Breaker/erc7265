// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

function max(uint256 x, uint256 y) pure returns (uint256 z) {
    /// @solidity memory-safe-assembly
    assembly {
        z := xor(x, mul(xor(x, y), gt(y, x)))
    }
}

function min(uint256 x, uint256 y) pure returns (uint256 z) {
    /// @solidity memory-safe-assembly
    assembly {
        z := xor(x, mul(xor(x, y), lt(y, x)))
    }
}

/**
 * @dev Subtraction between `x` and `y` resulting in `0` if normal `x - y` were to underflow.
 */
function cappedSub(uint256 x, uint256 y) pure returns (uint256 z) {
    /// @solidity memory-safe-assembly
    assembly {
        z := mul(sub(x, y), gt(x, y))
    }
}

function abs(int256 x) pure returns (uint256 y) {
    assembly {
        y := xor(x, mul(slt(x, 0), xor(sub(0, x), x)))
        if iszero(sub(y, shl(1, 255))) {
            // revert Panic(0x11)
            mstore(0x00, 0x4e487b71)
            mstore(0x20, 0x11)
            revert(0x1c, 0x24)
        }
    }
}

function deltaAdd(uint256 x, int256 delta) pure returns (uint256 z) {
    assembly {
        z := add(x, delta)
        if iszero(sgt(or(x, z), not(0))) {
            // revert Panic(0x11)
            mstore(0x00, 0x4e487b71)
            mstore(0x20, 0x11)
            revert(0x1c, 0x24)
        }
    }
}
