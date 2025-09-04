// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Math} from "./math/Math.sol";
import {Bytes} from "./Bytes.sol";

library RLP {
    function encode(bool input) internal pure returns (bytes memory result) {
        assembly ("memory-safe") {
            result := mload(0x40)
            mstore(result, 0x01)
            mstore(add(result, 0x20), shl(add(248, mul(7, iszero(input))), 1))
            mstore(0x40, add(result, 0x21))
        }
    }

    function encode(address input) internal pure returns (bytes memory result) {
        assembly ("memory-safe") {
            result := mload(0x40)
            mstore(result, 0x15)
            mstore(add(result, 0x20), or(shl(248, 0x94), shl(88, input)))
            mstore(0x40, add(result, 0x35))
        }
    }

    function encode(uint256 input) internal pure returns (bytes memory result) {
        if (input < 0x80) {
            assembly ("memory-safe") {
                result := mload(0x40)
                mstore(result, 1)
                mstore(add(result, 0x20), shl(248, or(input, mul(0x80, iszero(input)))))
                mstore(0x40, add(result, 0x21))
            }
        } else {
            uint256 length = Math.log256(input) + 1;
            assembly ("memory-safe") {
                result := mload(0x40)
                mstore(result, add(length, 1))
                mstore8(add(result, 0x20), add(length, 0x80))
                mstore(add(result, 0x21), shl(sub(256, mul(8, length)), input))
                mstore(0x40, add(result, add(length, 0x21)))
            }
        }
    }

    function encode(bytes memory input) internal pure returns (bytes memory) {
        return (input.length == 1 && uint8(input[0]) < 128) ? input : _encode(input, 0x80);
    }

    function encode(bytes[] memory input) internal pure returns (bytes memory) {
        return _encode(Bytes.concat(input), 0xc0);
    }

    function _encode(bytes memory input, uint256 offset) private pure returns (bytes memory result) {
        uint256 length = input.length;
        if (length < 56) {
            // Encode "short-bytes" as
            // [ 0x80 + input.length | input ]
            assembly ("memory-safe") {
                result := mload(0x40)
                mstore(result, add(length, 1))
                mstore8(add(result, 0x20), add(length, offset))
                mcopy(add(result, 0x21), add(input, 0x20), length)
                mstore(0x40, add(result, add(length, 0x21)))
            }
        } else {
            // Encode "long-bytes" as
            // [ 0xb7 + input.length.length | input.length | input ]
            uint256 lenlength = Math.log256(length) + 1;
            assembly ("memory-safe") {
                result := mload(0x40)
                mstore(result, add(add(length, lenlength), 1))
                mstore8(add(result, 0x20), add(add(lenlength, offset), 55))
                mstore(add(result, 0x21), shl(sub(256, mul(8, lenlength)), length))
                mcopy(add(result, add(lenlength, 0x21)), add(input, 0x20), length)
                mstore(0x40, add(result, add(add(length, lenlength), 0x21)))
            }
        }
    }
}
