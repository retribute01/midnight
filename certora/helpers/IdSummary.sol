// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {UtilsLib} from "../../src/libraries/UtilsLib.sol";
import {Obligation} from "../../src/interfaces/IMorphoV2.sol";

contract IdSummary {
    function toIdSummary(Obligation memory obligation, uint256, address) external pure returns (bytes32) {
        return keccak256(abi.encode(obligation));
    }
}
