// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

uint256 constant WAD = 1e18;
uint256 constant ORACLE_PRICE_SCALE = 1e36;
uint256 constant FEE_STEP = 1e12;
uint256 constant MAX_FEE = 0.01e18; // 1% (100 bps)
uint256 constant MAX_LIF = 1.15e18; // Liquidation Incentive Factor
uint256 constant TIME_TO_MAX_LIF = 15 minutes; // Time to reach MAX_LIF
bytes32 constant EIP712_DOMAIN_TYPEHASH = keccak256("EIP712Domain(uint256 chainId,address verifyingContract)");
bytes32 constant ROOT_TYPEHASH = keccak256("Root(bytes32 root)");

/// @dev Minimal creation code that returns the rest of creation code as runtime bytecode.
// hex       opcode          stack              comments
// --------------------------------------------------------------------------
// 60 0b     PUSH1 0x0b      [11]
// 38        CODESIZE        [codesize, 11]
// 03        SUB             [len]              with len = codesize - 11
// 80        DUP1            [len, len]
// 60 0b     PUSH1 0x0b      [11, len, len]     code offset = 11
// 5f        PUSH0           [0, 11, len, len]  mem offset = 0
// 39        CODECOPY        [len]              mem[0:len] <- code[11:11+len]
// 5f        PUSH0           [0, len]           return offset = 0
// f3        RETURN          []                 mem[0:len] is returned
bytes constant OBLIGATION_DEPLOYER_PREFIX = hex"600b380380600b5f395ff3";
