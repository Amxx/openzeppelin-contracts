// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.3.0) (utils/Calldata.sol)

pragma solidity ^0.8.20;

/**
 * @dev Helper library for manipulating objects in calldata.
 */
library Calldata {
    // slither-disable-next-line write-after-write
    function emptyBytes() internal pure returns (bytes calldata result) {
        assembly ("memory-safe") {
            result.offset := 0
            result.length := 0
        }
    }

    // slither-disable-next-line write-after-write
    function emptyString() internal pure returns (string calldata result) {
        assembly ("memory-safe") {
            result.offset := 0
            result.length := 0
        }
    }

    function decodeBytesAt(bytes calldata data, uint256 pos) internal pure returns (bytes calldata) {
        uint256 offset = uint256(bytes32(data[pos:]));
        uint256 length = uint256(bytes32(data[offset:]));
        return data[offset + 0x20:offset + 0x20 + length];
    }
}
