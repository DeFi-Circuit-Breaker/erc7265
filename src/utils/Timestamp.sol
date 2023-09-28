// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

uint256 constant _T32_MASK = 0xffffffff;

function delta(uint256 t2, uint256 t1) pure returns (uint256 dt) {
    /// @solidity memory-safe-assembly
    assembly {
        dt := and(_T32_MASK, sub(t2, t1))
    }
}

function since(uint256 t1) view returns (uint256 dt) {
    /// @solidity memory-safe-assembly
    assembly {
        dt := and(_T32_MASK, sub(timestamp(), t1))
    }
}
