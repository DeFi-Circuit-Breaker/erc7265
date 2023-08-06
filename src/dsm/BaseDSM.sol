// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {FixedPointMathLib as Math} from "solady/utils/FixedPointMathLib.sol";
import {DelayLib} from "../utils/DelayLib.sol";

/// @author philogy <https://github.com/philogy>
abstract contract BaseDSM {
    struct EffectState {
        uint128 scheduledAt;
        uint128 delay;
    }

    uint8 internal constant SIMPLE_PAYLOAD_VERSION = 0x00;
    uint8 internal constant MULTI_PAYLOAD_VERSION = 0x01;

    mapping(bytes32 => EffectState) internal _effects;

    event Scheduled(bytes32 indexed effectID, bytes effectData);
    event Executed(bytes32 indexed effectID);

    error InvalidValue();
    error UnrecognizedVersion(uint8 version);
    error NonexistentEffect(bytes32 effectID);
    error NotSettled(bytes32 effectID);
    error EffectFailed(bytes32 effectID);
    error UnauthorizedScheduler(address caller);

    constructor() {
        assert(block.timestamp > 0);
    }

    function schedule(address target, uint256 value, bytes calldata innerPayload)
        external
        payable
        returns (bytes32 newEffectID)
    {
        if (value != msg.value) revert InvalidValue();
        _checkSchedulerAuthorized(msg.sender);
        // Only `innerPayload` is variable length so it's safe to apply `encodePacked`.
        bytes memory effectData = abi.encodePacked(target, msg.value, _getUniqueNonce(), innerPayload);
        newEffectID = keccak256(effectData);
        _effects[newEffectID] = EffectState({scheduledAt: uint128(block.timestamp), delay: _currentDelay()});
        emit Scheduled(newEffectID, effectData);
        // Implicit return of `newEffectID`.
    }

    function execute(bytes calldata outerPayload) public {
        uint8 version = uint8(outerPayload[0]);
        if (version == SIMPLE_PAYLOAD_VERSION) {
            _execute(
                address(bytes20(outerPayload[1:21])),
                uint128(bytes16(outerPayload[21:37])),
                uint64(bytes8(outerPayload[37:45])),
                outerPayload[29:]
            );
        } else if (version == MULTI_PAYLOAD_VERSION) {
            uint256 payloadLength = outerPayload.length;
            uint256 i = 1;
            while (i < payloadLength) {
                unchecked {
                    uint256 nextLength = uint24(bytes3(outerPayload[i:i += 3]));
                    execute(outerPayload[i:i += nextLength]);
                }
            }
        } else {
            revert UnrecognizedVersion(version);
        }
    }

    function pausedTill() public view virtual returns (uint256);

    function _execute(address target, uint256 value, uint64 nonce, bytes calldata innerPayload) internal {
        bytes32 effectID = keccak256(abi.encodePacked(target, value, nonce, innerPayload));
        EffectState memory estate = _effects[effectID];
        if (estate.scheduledAt == 0) revert NonexistentEffect(effectID);
        uint256 settlementTime = _getSettlementTime(estate);
        if (settlementTime < Math.max(block.timestamp, pausedTill())) revert NotSettled(effectID);
        delete _effects[effectID];
        (bool success,) = target.call{value: value}(innerPayload);
        if (!success) revert EffectFailed(effectID);
        emit Executed(effectID);
    }

    function _checkSchedulerAuthorized(address scheduler) internal virtual;

    function _getUniqueNonce() internal virtual returns (uint64);

    function _currentDelay() internal view virtual returns (uint128);

    function _validSince() internal view virtual returns (uint256);

    function _getSettlementTime(EffectState memory estate) internal view returns (uint256) {
        return DelayLib.getSettlementTime(estate.scheduledAt, estate.delay, _currentDelay(), _validSince());
    }
}
