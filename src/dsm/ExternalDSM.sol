// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "solady/auth/Ownable.sol";
import {SafeCastLib} from "solady/utils/SafeCastLib.sol";
import {BaseDSM} from "./BaseDSM.sol";
import {DelayLib} from "../utils/DelayLib.sol";

/// @author philogy <https://github.com/philogy>
contract ExternalDSM is Ownable, BaseDSM {
    using SafeCastLib for uint256;

    uint40 internal lastPaused;
    bool public paused;
    uint64 internal effectNonce;
    uint40 public currentDelay;
    uint40 public validSince;

    mapping(address => bool) public approvedScheduler;

    event Paused();
    event Unpaused();
    event DelaySet(uint256 delay);
    event SchedulerAdded(address indexed scheduler);
    event SchedulerRemoved(address indexed scheduler);

    error CurrentlyPaused();
    error CurrentlyUnpaused();
    error AlreadyScheduler(address scheduler);
    error NotScheduler(address scheduler);

    constructor(address initialOwner, uint40 startDelay) {
        _initializeOwner(initialOwner);
        validSince = uint40(block.timestamp);
        _setDelay(startDelay);
    }

    modifier whenNotPaused() {
        if (paused) revert CurrentlyPaused();
        _;
    }

    modifier whenPaused() {
        if (!paused) revert CurrentlyUnpaused();
        _;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setDelay(uint40 newDelay) external onlyOwner {
        uint256 newValidity = DelayLib.getNewValidity(currentDelay, validSince);
        validSince = newValidity.toUint40();
        _setDelay(newDelay);
    }

    function addScheduler(address scheduler) external onlyOwner {
        if (approvedScheduler[scheduler]) revert AlreadyScheduler(scheduler);
        approvedScheduler[scheduler] = true;
        emit SchedulerAdded(scheduler);
    }

    function removeScheduler(address scheduler) external onlyOwner {
        if (!approvedScheduler[scheduler]) revert NotScheduler(scheduler);
        approvedScheduler[scheduler] = false;
        emit SchedulerRemoved(scheduler);
    }

    function pausedTill() public view override returns (uint256) {
        if (paused) return type(uint256).max;
        return lastPaused;
    }

    function _getUniqueNonce() internal override returns (uint64) {
        unchecked {
            return effectNonce++;
        }
    }

    function _pause() internal whenNotPaused {
        paused = true;
        emit Paused();
    }

    function _unpause() internal whenPaused {
        paused = false;
        lastPaused = uint40(block.timestamp);
        emit Unpaused();
    }

    function _setDelay(uint40 delay) internal {
        currentDelay = delay;
        emit DelaySet(delay);
    }

    function _currentDelay() internal view override returns (uint128) {
        return currentDelay;
    }

    function _validSince() internal view override returns (uint256) {
        return validSince;
    }

    function _checkSchedulerAuthorized(address scheduler) internal view override {
        if (!approvedScheduler[scheduler] && owner() != scheduler) revert UnauthorizedScheduler(scheduler);
    }
}
