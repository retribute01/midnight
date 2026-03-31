// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.31;

import {IRatifier} from "./interfaces/ICallbacks.sol";
import {Offer} from "./interfaces/IMidnight.sol";
import {CALLBACK_SUCCESS} from "./libraries/ConstantsLib.sol";

contract PreapprovalRatifier is IRatifier {
    mapping(address maker => mapping(bytes32 root => bool)) public approved;

    function setApproval(bytes32 root, bool newApproval) external {
        approved[msg.sender][root] = newApproval;
    }

    function onRatify(Offer memory offer, bytes32 root, bytes memory) external returns (bytes32) {
        require(approved[offer.maker][root], "not approved");
        return CALLBACK_SUCCESS;
    }
}
