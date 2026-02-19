// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Obligation} from "../interfaces/IMorphoV2.sol";
import {UtilsLib} from "./UtilsLib.sol";

library IdLib {
    function toId(Obligation memory obligation, uint256 chainId, address morphoV2) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                uint8(0xff),
                morphoV2,
                chainId,
                keccak256(abi.encodePacked(UtilsLib.SSTORE2_PREFIX, abi.encode(obligation)))
            )
        );
    }

    function toObligation(bytes32 id) internal view returns (Obligation memory) {
        return abi.decode(address(uint160(uint256(id))).code, (Obligation));
    }
}
