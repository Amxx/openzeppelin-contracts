// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {RLP} from "@openzeppelin/contracts/utils/RLP.sol";

contract RLPTest is Test {
    using RLP for *;

    function testEncodeEmpty() external pure {
        assertEq(RLP.encoder().encode(), hex"c0");
    }

    function testEncodeUint256(uint256 input) external pure {
        bytes[] memory list = new bytes[](1);
        list[0] = RLP.encode(input);

        assertEq(RLP.encoder().push(input).encode(), RLP.encode(list));
    }

    function testEncodeAddress(address input) external pure {
        bytes[] memory list = new bytes[](1);
        list[0] = RLP.encode(input);

        assertEq(RLP.encoder().push(input).encode(), RLP.encode(list));
    }

    function testEncodeBytes(bytes memory input) external pure {
        bytes[] memory list = new bytes[](1);
        list[0] = RLP.encode(input);

        assertEq(RLP.encoder().push(input).encode(), RLP.encode(list));
    }

    /// forge-config: default.fuzz.runs = 512
    function testEncodeBytesArray(bytes[] memory input) external pure {
        bytes[] memory list = new bytes[](input.length);
        for (uint256 i = 0; i < input.length; ++i) {
            list[i] = RLP.encode(input[i]);
        }

        RLP.Encoder memory enc = RLP.encoder();
        for (uint256 i = 0; i < input.length; ++i) {
            enc.push(input[i]);
        }
        assertEq(enc.encode(), RLP.encode(list));
    }

    function testEncodeMultiType(uint256 u, bytes memory b, address a) external pure {
        bytes[] memory list = new bytes[](3);
        list[0] = RLP.encode(u);
        list[1] = RLP.encode(b);
        list[2] = RLP.encode(a);

        assertEq(RLP.encoder().push(u).push(b).push(a).encode(), RLP.encode(list));

        list[0] = RLP.encode(b);
        list[1] = RLP.encode(a);
        list[2] = RLP.encode(u);

        assertEq(RLP.encoder().push(b).push(a).push(u).encode(), RLP.encode(list));
    }
}
