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

/**
 * @dev Turns a signed integer into an unsigned one, removing the sign if negative. Note that unlike
 * Solidity's unary `-x` operator this function will not revert if `x` is equal to -2^255 which has
 * the same representation as +2^255.
 */
function abs(int256 x) pure returns (uint256 y) {
    assembly {
        y := xor(x, mul(slt(x, 0), xor(sub(0, x), x)))
    }
}

function deltaAdd(uint256 x, int256 delta) pure returns (uint256 z) {
    assembly {
        z := add(x, delta)
        if iszero(eq(lt(z, x), slt(delta, 0))) {
            // revert Panic(0x11)
            mstore(0x00, 0x4e487b71)
            mstore(0x20, 0x11)
            revert(0x1c, 0x24)
        }
    }
}

function sign(int256 x) pure returns (int256 s) {
    assembly {
        s := sub(1, shl(1, slt(x, 0)))
    }
}

function signNeg(int256 x) pure returns (int256 s) {
    assembly {
        s := sub(shl(1, slt(x, 0)), 1)
    }
}
