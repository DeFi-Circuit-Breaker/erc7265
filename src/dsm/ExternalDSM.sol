// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {OwnableRoles} from "solady/auth/OwnableRoles.sol";
import {SafeCastLib} from "solady/utils/SafeCastLib.sol";
import {Pausable} from "openzeppelin/security/Pausable.sol";
import {BaseDSM} from "./BaseDSM.sol";

/// @author philogy <https://github.com/philogy>
contract ExternalDSM is OwnableRoles, BaseDSM, Pausable {
    using SafeCastLib for uint256;

    uint40 internal lastPaused;
    uint64 internal effectNonce;
    uint40 public currentDelay;

    uint256 public constant AUTHORIZED_SCHEDULER_ROLE = _ROLE_0;

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

    function schedule(address target, uint256 value, bytes calldata innerPayload)
        external
        payable
        returns (bytes32 newEffectID)
    {
        if (value != msg.value) revert InvalidValue();
        return _schedule(target, msg.value, innerPayload);
    }

    function pausedTill() public view override returns (uint256) {
        if (paused()) return type(uint256).max;
        return lastPaused;
    }

    function _getUniqueNonce() internal override returns (uint64) {
        unchecked {
            return effectNonce++;
        }
    }

    function _unpause() internal override {
        lastPaused = uint40(block.timestamp);
        super._unpause();
    }

    function _setDelay(uint40 delay) internal {
        currentDelay = delay;
        emit DelaySet(delay);
    }

    function _currentDelay() internal view override returns (uint128) {
        return currentDelay;
    }

    function _checkSchedulerAuthorized(address scheduler) internal view override {
        if (!hasAnyRole(scheduler, AUTHORIZED_SCHEDULER_ROLE)) revert Unauthorized();
    }
}
