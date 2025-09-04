// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Math} from "./math/Math.sol";
import {Bytes} from "./Bytes.sol";
import {Memory} from "./Memory.sol";

library RLP {
    struct Encoder {
        Memory.Pointer head;
        Memory.Pointer tail;
    }

    struct Item {
        Memory.Pointer next;
        bytes data;
    }

    function encoder() internal pure returns (Encoder memory self) {
        self.head = Memory.asPointer(0x00);
        self.tail = Memory.asPointer(0x00);
    }

    function push(Encoder memory self, bool input) internal pure returns (Encoder memory) {
        return _push(self, encode(input));
    }

    function push(Encoder memory self, address input) internal pure returns (Encoder memory) {
        return _push(self, encode(input));
    }

    function push(Encoder memory self, uint256 input) internal pure returns (Encoder memory) {
        return _push(self, encode(input));
    }

    function push(Encoder memory self, bytes memory input) internal pure returns (Encoder memory) {
        return _push(self, encode(input));
    }

    function push(Encoder memory self, Encoder memory input) internal pure returns (Encoder memory) {
        return _push(self, encode(input));
    }

    function _asPtr(Item memory item) private pure returns (Memory.Pointer ptr) {
        assembly ("memory-safe") {
            ptr := item
        }
    }

    function _asItem(Memory.Pointer ptr) private pure returns (Item memory item) {
        assembly ("memory-safe") {
            item := ptr
        }
    }

    function _push(Encoder memory self, bytes memory data) private pure returns (Encoder memory) {
        Memory.Pointer ptr = _asPtr(Item(Memory.asPointer(0x00), data));

        // list new item after the current tail
        _asItem(self.tail).next = ptr;
        // Update to tail to point to the new item
        self.tail = ptr;
        // If there is no head, the list is empty and thus the item is the first one.
        if (Memory.asBytes32(self.head) == 0x00) {
            self.head = ptr;
        }
        return self;
    }

    function _flatten(Encoder memory self) private pure returns (bytes memory result) {
        assembly ("memory-safe") {
            result := mload(0x40)
            let ptr := add(result, 0x20)
            for {
                let it := mload(self)
            } iszero(iszero(it)) {
                it := mload(it)
            } {
                let buffer := mload(add(it, 0x20))
                let length := mload(buffer)
                mcopy(ptr, add(buffer, 0x20), length)
                ptr := add(ptr, length)
            }
            mstore(result, sub(ptr, add(result, 0x20)))
            mstore(0x40, ptr)
        }
    }

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

    function encode(Encoder memory input) internal pure returns (bytes memory) {
        return _encode(_flatten(input), 0xc0);
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
