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
