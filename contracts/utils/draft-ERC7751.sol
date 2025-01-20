// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Address} from "./Address.sol";

library ERC7751 {
    error WrappedError(address target, bytes4 selector, bytes reason, bytes details);

    function sendValue(address target, uint256 value, bytes memory details) internal returns (bytes memory) {
        return functionCallWithValue(target, value, bytes(""), details);
    }

    function functionCall(address target, bytes memory data, bytes memory details) internal returns (bytes memory) {
        return functionCallWithValue(target, 0, data, details);
    }

    function functionCallWithValue(
        address target,
        uint256 value,
        bytes memory data,
        bytes memory details
    ) internal returns (bytes memory) {
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResult(success, target, data, returndata, details, value == 0 || data.length > 0);
    }

    function functionStaticCall(
        address target,
        bytes memory data,
        bytes memory details
    ) internal view returns (bytes memory) {
        (bool success, bytes memory returndata) = target.staticcall(data);
        return verifyCallResult(success, target, data, returndata, details, true);
    }

    function functionDelegateCall(
        address target,
        bytes memory data,
        bytes memory details
    ) internal returns (bytes memory) {
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return verifyCallResult(success, target, data, returndata, details, true);
    }

    function verifyCallResult(
        bool success,
        address target,
        bytes memory data,
        bytes memory returndata,
        bytes memory details,
        bool requireCode
    ) internal view returns (bytes memory) {
        if (!success) {
            revert WrappedError(target, bytes4(data), returndata, details);
        } else if (requireCode && returndata.length == 0 && target.code.length == 0) {
            revert Address.AddressEmptyCode(target);
        } else {
            return returndata;
        }
    }
}
