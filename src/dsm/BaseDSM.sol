// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @author philogy <https://github.com/philogy>
abstract contract BaseDSM {
    enum PayloadVersion {
        NormalExecute,
        MultiPayload,
        Confirmed
    }

    mapping(bytes32 => uint256) public settleTimeOf;

    event Scheduled(bytes32 indexed effectId, bytes effectData);
    event Executed(bytes32 indexed effectId);

    error InvalidValue();
    error UnsupportedVersion(PayloadVersion version);
    error NonexistentEffect(bytes32 effectId);
    error NotSettled(bytes32 effectId);
    error EffectFailed(bytes32 effectId);
    error UnauthorizedScheduler(address caller);

    constructor() {
        assert(block.timestamp > 0);
    }

    function execute(bytes calldata outerPayload) public {
        PayloadVersion version = PayloadVersion(uint8(outerPayload[0]));
        uint256 i = 1;
        if (version == PayloadVersion.NormalExecute) {
            // Effect's who's settlement time has passed and can be normally executed.
            (address target, uint256 value, uint64 nonce, bytes calldata innerPayload) =
                _decodeEffect(i, outerPayload[i:]);
            _executeNormalSettled(target, value, nonce, innerPayload);
        } else if (version == PayloadVersion.MultiPayload) {
            // Efficient multicall for effect execution.
            uint256 payloadLength = outerPayload.length;
            bytes calldata nextPayload;
            while (i < payloadLength) {
                (i, nextPayload) = _decodeVarLength(i, outerPayload[i:]);
                execute(nextPayload);
            }
        } else if (version == PayloadVersion.Confirmed) {
            // Effect that can/needs to be settled with an extra "confirmation proof" e.g. paused effects.
            bytes calldata confirmProof;
            (i, confirmProof) = _decodeVarLength(i, outerPayload[i:]);
            (address target, uint256 value, uint64 nonce, bytes calldata innerPayload) =
                _decodeEffect(i, outerPayload[i:]);
            _executeConfirmedEffect(confirmProof, target, value, nonce, innerPayload);
        } else {
            revert UnsupportedVersion(version);
        }
    }

    function pausedTill() public view virtual returns (uint256);

    function _schedule(address target, uint256 value, bytes memory innerPayload)
        internal
        returns (bytes32 newEffectId)
    {
        // Only `innerPayload` is variable length so it's safe to apply `encodePacked` + hashing.
        bytes memory effectData = abi.encodePacked(target, value, _getUniqueNonce(), innerPayload);
        newEffectId = keccak256(effectData);
        settleTimeOf[newEffectId] = block.timestamp + _currentDelay();
        emit Scheduled(newEffectId, effectData);
        // Implicit return of `newEffectId`.
    }

    function _decodeEffect(uint256 i, bytes calldata data)
        internal
        pure
        returns (address target, uint256 value, uint64 nonce, bytes calldata innerPayload)
    {
        unchecked {
            target = address(bytes20(data[i:i += 20]));
            value = uint128(bytes16(data[i:i += 16]));
            nonce = uint64(bytes8(data[i:i += 8]));
            innerPayload = data[i:];
        }
    }

    function _executeNormalSettled(address target, uint256 value, uint64 nonce, bytes calldata innerPayload) internal {
        (bytes32 effectId, uint256 settlesAt) = _validateEffectExists(target, value, nonce, innerPayload);
        if (settlesAt > block.timestamp || settlesAt <= pausedTill()) revert NotSettled(effectId);
        _executeEffect(effectId, target, value, innerPayload);
    }

    function _executeConfirmedEffect(
        bytes calldata confirmProof,
        address target,
        uint256 value,
        uint64 nonce,
        bytes calldata innerPayload
    ) internal {
        (bytes32 effectId,) = _validateEffectExists(target, value, nonce, innerPayload);
        _checkConfirmation(effectId, confirmProof);
        _executeEffect(effectId, target, value, innerPayload);
    }

    function _executeEffect(bytes32 effectId, address target, uint256 value, bytes calldata innerPayload) internal {
        delete settleTimeOf[effectId];
        (bool success,) = target.call{value: value}(innerPayload);
        if (!success) revert EffectFailed(effectId);
        emit Executed(effectId);
    }

    function _validateEffectExists(address target, uint256 value, uint64 nonce, bytes calldata innerPayload)
        internal
        view
        returns (bytes32, uint256)
    {
        bytes32 effectId = keccak256(abi.encodePacked(target, value, nonce, innerPayload));
        uint256 settlesAt = settleTimeOf[effectId];
        if (settlesAt == 0) revert NonexistentEffect(effectId);
        return (effectId, settlesAt);
    }

    function _getUniqueNonce() internal virtual returns (uint64);

    function _currentDelay() internal view virtual returns (uint128);

    function _checkConfirmation(bytes32 effectId, bytes calldata confirmationProof) internal virtual;

    function _decodeVarLength(uint256 i, bytes calldata buffer) internal pure returns (uint256, bytes calldata) {
        unchecked {
            uint256 nextLength = uint24(bytes3(buffer[i:i += 3]));
            bytes calldata decoded = buffer[i:i += nextLength];
            return (i, decoded);
        }
    }
}
