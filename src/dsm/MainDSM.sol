// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {BaseDSM} from "./BaseDSM.sol";

/// @author philogy <https://github.com/philogy>
abstract contract MainDSM is BaseDSM, Pausable {
    uint40 public currentDelay;
    uint40 internal _lastPaused;
    uint64 internal _effectNonce;

    event DelaySet(uint256 delay);

    error NotSettlementMaster();

    constructor(uint40 startDelay) {
        _setDelay(startDelay);
    }

    modifier onlySettlementMaster() {
        if (msg.sender != settlementMaster()) revert NotSettlementMaster();
        _;
    }

    function pause() external onlySettlementMaster {
        _pause();
    }

    function unpause() external onlySettlementMaster {
        _unpause();
    }

    function setDelay(uint40 newDelay) external onlySettlementMaster {
        _setDelay(newDelay);
    }

    function pausedTill() public view override returns (uint256) {
        return paused() ? type(uint256).max : _lastPaused;
    }

    function settlementMaster() public view virtual returns (address);

    function _getUniqueNonce() internal override returns (uint64) {
        unchecked {
            return _effectNonce++;
        }
    }

    function _unpause() internal override {
        _lastPaused = uint40(block.timestamp);
        super._unpause();
    }

    function _setDelay(uint40 delay) internal virtual {
        emit DelaySet(currentDelay = delay);
    }

    function _currentDelay() internal view override returns (uint128) {
        return currentDelay;
    }
}
