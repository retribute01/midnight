// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

contract SStore2 {
    constructor(bytes memory data) {
        assembly ("memory-safe") {
            return(add(data, 0x20), mload(data))
        }
    }
}
