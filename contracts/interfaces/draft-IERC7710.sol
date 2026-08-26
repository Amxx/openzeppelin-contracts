// SPDX-License-Identifier: MIT

pragma solidity >=0.6.2;

/**
 * @title IERC7710Manager
 * @notice Interface for Delegation Manager that exposes the redeemDelegations function.
 */
interface IERC7710Manager {
    /**
     * @notice This method validates the provided permission contexts and executes the execution if the caller has authority to do so.
     * @dev the structure of the _permissionContexts bytes[] is determined by the specific Delegation Manager implementation
     * @param _permissionContexts the data used to validate the authority given to execute the corresponding execution.
     * @param _action the action to be executed
     * @param _modes the array of modes to execute the related executioncallData
     * @param _executionCallDatas the array of encoded executions to be executed
     */
  function redeemDelegations(
    bytes[] calldata _permissionContexts,
    bytes32[] calldata _modes,
    bytes[] calldata _executionCallData
  ) external;
}