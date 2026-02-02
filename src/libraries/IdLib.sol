// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Obligation} from "../interfaces/IMorphoV2.sol";

library IdLib {
    /// @dev Minimal creation code that returns code after the prefix as runtime bytecode.
    /// @dev Explanation of the prefix:
    /// hex       opcode          stack              comments
    /// --------------------------------------------------------------------------
    /// 60 0b     PUSH1 0x0b      [11]
    /// 38        CODESIZE        [codesize, 11]
    /// 03        SUB             [len]              with len = codesize - 11
    /// 80        DUP1            [len, len]
    /// 60 0b     PUSH1 0x0b      [11, len, len]     code offset = 11
    /// 5f        PUSH0           [0, 11, len, len]  mem offset = 0
    /// 39        CODECOPY        [len]              mem[0:len] <- code[11:11+len]
    /// 5f        PUSH0           [0, len]           return offset = 0
    /// f3        RETURN          []                 mem[0:len] is returned
    function creationCode(Obligation memory obligation, uint256 chainid, address morphoV2)
        internal
        pure
        returns (bytes memory)
    {
        bytes memory prefix = hex"600b380380600b5f395ff3";
        bytes memory sstore2Data = abi.encode(obligation, chainid, morphoV2);
        return abi.encodePacked(prefix, sstore2Data);
    }

    function toId(Obligation memory obligation, uint256 chainid, address morphoV2) internal pure returns (bytes32) {
        return keccak256(creationCode(obligation, chainid, morphoV2));
    }

    function idToObligation(address morphoV2, bytes32 id) internal view returns (Obligation memory) {
        address create2Address =
            address(uint160(uint256(keccak256(abi.encodePacked(uint8(0xff), morphoV2, bytes32(0), id)))));
        (Obligation memory obligation,,) = abi.decode(create2Address.code, (Obligation, uint256, address));
        return obligation;
    }

    function sstore2(Obligation memory obligation) internal {
        bytes memory _creationCode = creationCode(obligation, block.chainid, address(this));
        address create2Address;
        assembly ("memory-safe") {
            create2Address := create2(0, add(_creationCode, 0x20), mload(_creationCode), 0)
        }
        require(create2Address != address(0), "Failed to create SStore2 contract");
    }
}
