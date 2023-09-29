// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

type FungibleAsset is address;

FungibleAsset constant NATIVE = FungibleAsset.wrap(address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE));

function eq(FungibleAsset a, FungibleAsset b) pure returns (bool) {
    return FungibleAsset.unwrap(a) == FungibleAsset.unwrap(b);
}

using FungibleAssetLib for FungibleAsset global;
using {eq as ==} for FungibleAsset global;

/// @author philogy <https://github.com/philogy>
library FungibleAssetLib {
    using SafeTransferLib for address;

    error NativeAssetNotToken();
    error NoCodeAtTokenAddress();
    error NativeAssetDoesntSupportTransferViaAllowance();

    function fromTokenAddress(address token) internal pure returns (FungibleAsset) {
        if (token == FungibleAsset.unwrap(NATIVE)) revert NativeAssetNotToken();
        return FungibleAsset.wrap(token);
    }

    function transfer(FungibleAsset asset, address recipient, uint256 amount) internal {
        if (asset == NATIVE) {
            recipient.safeTransferETH(amount);
        } else {
            address tokenAddr = FungibleAsset.unwrap(asset);
            tokenAddr.safeTransfer(recipient, amount);
            // Solady doesn't have codesize check in `safeTransfer`
            if (tokenAddr.code.length == 0) revert NoCodeAtTokenAddress();
        }
    }

    function transferFrom(FungibleAsset asset, address from, address to, uint256 amount) internal {
        if (asset == NATIVE) revert NativeAssetDoesntSupportTransferViaAllowance();
        address tokenAddr = FungibleAsset.unwrap(asset);
        tokenAddr.safeTransferFrom(from, to, amount);
        // Solady doesn't have codesize check in `safeTransfer`
        if (tokenAddr.code.length == 0) revert NoCodeAtTokenAddress();
    }

    function balanceOfThis(FungibleAsset asset) internal view returns (uint256) {
        if (asset == NATIVE) {
            return address(this).balance;
        } else {
            return FungibleAsset.unwrap(asset).balanceOf(address(this));
        }
    }
}
