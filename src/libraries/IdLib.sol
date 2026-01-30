// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {ObligationDeployer} from "../ObligationDeployer.sol";
import {Obligation} from "../interfaces/IMorphoV2.sol";

library IdLib {
    function toId(Obligation memory obligation, uint256 chainid, address morphoV2) internal pure returns (bytes32) {
        bytes memory creationCode =
            abi.encodePacked(type(ObligationDeployer).creationCode, abi.encode(obligation, chainid, morphoV2));
        return keccak256(creationCode);
    }

    function idToObligationContract(address morphoV2, bytes32 id) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(uint8(0xff), morphoV2, bytes32(0), id)))));
    }

    function idToObligation(address morphoV2, bytes32 id) internal view returns (Obligation memory) {
        address obligationContract = idToObligationContract(morphoV2, id);
        return abi.decode(obligationContract.code, (Obligation));
    }
}
