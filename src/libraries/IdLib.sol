// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Obligation} from "../interfaces/IMorphoV2.sol";

library IdLib {
    /// @dev Minimal creation code that returns code after the prefix as runtime bytecode.
    /// @dev Explanation of the prefix:
    /// hex       opcode          stack              comments
    /// ---------------------------------------------------------------------------------------
    /// 60 52     PUSH1 0x52      [82]                82 = 18 (prefix len) + 64 (removed words)
    /// 38        CODESIZE        [codesize, 82]
    /// 03        SUB             [len]               with len = codesize - 82
    /// 80        DUP1            [len, len]
    /// 60 52     PUSH1 0x52      [82, len, len]      code offset = 82
    /// 5f        PUSH0           [0, 82, len, len]   mem offset = 0
    /// 39        CODECOPY        [len]               mem[0:len] <- code[82:82+len]
    /// 60 40     PUSH 0x40       [64, len]
    /// 5f        PUSH0           [0, 64, len]        push 0 to the stack
    /// 51        MLOAD           [offset, 64, len]   offset = mem[0:32]
    /// 03        SUB             [newOffset, len]    newOffset removes 2 words (64 bytes)
    /// 5f        PUSH0           [0, newOffset, len] push 0 to the stack
    /// 52        MSTORE          [len]               mem[0:32] <- newOffset
    /// 5f        PUSH0           [0, len]            return offset = 0
    /// f3        RETURN          []                  mem[0:len] is returned
    function creationCode(Obligation memory obligation, uint256 chainId, address morphoV2)
        internal
        pure
        returns (bytes memory)
    {
        bytes memory prefix = hex"605238038060525f3960405f51035f525ff3";
        bytes memory sstore2Data = abi.encode(chainId, morphoV2, obligation);
        return abi.encodePacked(prefix, sstore2Data);
    }

    function toId(Obligation memory obligation, uint256 chainId, address morphoV2) internal pure returns (bytes32) {
        return keccak256(creationCode(obligation, chainId, morphoV2));
    }

    function idToObligation(address morphoV2, bytes32 id) internal view returns (Obligation memory) {
        address create2Address =
            address(uint160(uint256(keccak256(abi.encodePacked(uint8(0xff), morphoV2, bytes32(0), id)))));
        return abi.decode(create2Address.code, (Obligation));
    }

    /// @dev The contract code begins with 0x00 (STOP), because the first word is the offset of the obligation.
    function sstore2(Obligation memory obligation) internal {
        bytes memory _creationCode = creationCode(obligation, block.chainid, address(this));
        address create2Address;
        assembly ("memory-safe") {
            create2Address := create2(0, add(_creationCode, 0x20), mload(_creationCode), 0)
        }
        require(create2Address != address(0), "Failed to create SStore2 contract");
    }
}
