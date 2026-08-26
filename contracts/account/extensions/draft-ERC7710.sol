// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { IERC7710Manager } from "../../interfaces/draft-IERC7710.sol";
import { IERC7579Execution } from "../../interfaces/draft-IERC7579.sol";

/**
 * @title Example7710Manager
 * @notice Not for production use.A minimal reference implementation for ERC-7710 focusing on delegation redemption.
 * @dev This is an intentionally simplified implementation to demonstrate core concepts.
 * For a complete production implementation with features like conditional permission enforcement and revocation, see MetaMask's Delegation Framework:
 * https://github.com/MetaMask/delegation-framework/blob/main/src/DelegationManager.sol
 */
contract ERC7710Manager is IERC7710Manager, EIP712("DelegationManager", "1") {
    bytes32 public constant DELEGATION_TYPEHASH = keccak256("Delegation(bytes32 authority,bytes delegator,bytes delegate)");

    mapping(bytes32 delegationHash => bool isDisabled) public disabledDelegations;

    struct Delegation {
        bytes32 authority; // The authority being delegated (or ROOT_AUTHORITY)
        bytes delegator;   // Delegating authority (ERC-7913)
        bytes delegate;    // Receiving authority (ERC-7913)
        bytes signature;   // The delegator's signature authorizing this delegation
    }

    error LengthMismatch();
    error InvalidDelegator();
    error InvalidDelegate();
    error InvalidAuthority();
    error InvalidSignature();


    function disableDelegation(Delegation calldata delegation) public virtual {
        bytes32 delegationHash = hashDelegation(delegation);
        // TODO: use some invalidation signature (include nonce ?)
        // require(SignatureChecker.isValidSignatureNow(delegation.delegator, delegationHash, delegation.signature), InvalidSignature());
        require(!disabledDelegations[delegationHash], AlreadyDisabled());
        disabledDelegations[delegationHash] = true;
        // TODO: emit event
    }

    function enableDelegation(Delegation calldata delegation) public virtual {
        bytes32 delegationHash = hashDelegation(delegation);
        // TODO: use some invalidation signature (include nonce ?)
        // require(SignatureChecker.isValidSignatureNow(delegation.delegator, delegationHash, delegation.signature), InvalidSignature());
        require(disabledDelegations[delegationHash], AlreadyEnabled());
        disabledDelegations[delegationHash] = false;
        // TODO: emit event
    }

    /**
     * @notice Validates and executes delegated actions through a chain of authority.
     * @param _permissionContexts Array of delegation chains, each ordered from leaf to root.
     * Each chain demonstrates authority where:
     * - Index 0 is the leaf delegation (msg.sender's authority)
     * - Each delegation points to its authority via the previous delegation's hash
     * - The last delegation must have ROOT_AUTHORITY
     * @param _modes Execution modes for each action (see ERC-7579)
     * @param _executionCallDatas Encoded actions to execute
     */
    function redeemDelegations(
        bytes[] calldata _permissionContexts,
        bytes32[] calldata _modes,
        bytes[] calldata _executionCallDatas
    ) public virtual {
        uint256 length = _permissionContexts.length;
        require(length == _modes.length && length == _executionCallDatas.length, LengthMismatch());

        for (uint256 i = 0; i < length; ++i) {
            Delegation[] memory delegations = abi.decode(_permissionContexts[i], (Delegation[]));

            // Go over each delegation, from the root one to the most derived one, to validate the delegation chain
            bytes32 previousDelegationHash;
            for (uint256 j = 0; j < delegations.length; ++j) {
                Delegation memory delegation = delegations[j];

                bytes32 delegationHash = hashDelegation(delegation);
                require(SignatureChecker.isValidSignatureNow(delegation.delegator, delegationHash, delegation.signature), InvalidSignature());

                if (j == 0) {
                    require(delegation.authority == bytes32(0), InvalidAuthority()); // Root authority
                } else {
                    bytes memory previousDelegate = delegations[j - 1].delegate;
                    require(delegation.authority == previousDelegationHash, InvalidAuthority());
                    require(previousDelegate.equal(delegation.delegator) || previousDelegate.length == 0, InvalidDelegate());
                }

                previousDelegationHash = delegationHash;
            }

            // Validate caller is the end delegate
            bytes20 memory delegate = delegations[delegations.length - 1].delegate;
            require(delegate.length == 0 || (delegate.length == 20 && address(delegate) == msg.sender), InvalidDelegate());

            // Perform execution
            IERC7579Execution(delegations[0].delegator).executeFromExecutor(_modes[i], _executionCallDatas[i]);
        }
    }

    function hashDelegation(Delegation memory delegation) public pure returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        DELEGATION_TYPEHASH,
                        delegation.authority,
                        keccak256(delegation.delegator),
                        keccak256(delegation.delegate)
                    )
                )
            );
    }

    // TODO: revocate delegation
}