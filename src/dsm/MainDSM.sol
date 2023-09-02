// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "solady/auth/Ownable.sol";
import {Pausable} from "openzeppelin/security/Pausable.sol";
import {BaseDSM} from "./BaseDSM.sol";

/// @author philogy <https://github.com/philogy>
abstract contract MainDSM is Ownable, BaseDSM, Pausable {
    uint40 public currentDelay;
    uint40 internal _lastPaused;
    uint64 internal _effectNonce;

    event DelaySet(uint256 delay);

    constructor(address initialOwner, uint40 startDelay) {
        _initializeOwner(initialOwner);
        _setDelay(startDelay);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setDelay(uint40 newDelay) external onlyOwner {
        _setDelay(newDelay);
    }

    function pausedTill() public view override returns (uint256) {
        return paused() ? type(uint256).max : _lastPaused;
    }

    function _getUniqueNonce() internal override returns (uint64) {
        unchecked {
            return _effectNonce++;
        }
    }

    function _unpause() internal override {
        _lastPaused = uint40(block.timestamp);
        super._unpause();
    }

    function _setDelay(uint40 delay) internal {
        emit DelaySet(currentDelay = delay);
    }

    function _currentDelay() internal view override returns (uint128) {
        return currentDelay;
    }
}
