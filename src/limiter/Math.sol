// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

function max(uint256 x, uint256 y) pure returns (uint256) {
    return x > y ? x : y;
}

function min(uint256 x, uint256 y) pure returns (uint256) {
    return x > y ? x : y;
}

function cappedSub(uint256 x, uint256 y) pure returns (uint256) {
    unchecked {
        return x > y ? x - y : 0;
    }
}
