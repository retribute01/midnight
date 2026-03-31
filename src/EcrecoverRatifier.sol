// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.31;

import {IRatifier} from "./interfaces/ICallbacks.sol";
import {Offer, Signature} from "./interfaces/IMidnight.sol";
import {CALLBACK_SUCCESS, EIP712_DOMAIN_TYPEHASH, ROOT_TYPEHASH} from "./libraries/ConstantsLib.sol";

interface IIsAuthorized {
    function isAuthorized(address authorizer, address authorized) external view returns (bool);
}

contract EcrecoverRatifier is IRatifier {
    function onRatify(Offer memory offer, bytes32 root, bytes memory data) external returns (bytes32) {
        Signature memory sig = abi.decode(data, (Signature));
        bytes32 hashStruct = keccak256(abi.encode(ROOT_TYPEHASH, root));
        bytes32 domainSeparator = keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, msg.sender));
        bytes32 digest = keccak256(bytes.concat("\x19\x01", domainSeparator, hashStruct));
        address signer = ecrecover(digest, sig.v, sig.r, sig.s);
        require(signer != address(0), "invalid signature");
        require(
            signer == offer.maker || IIsAuthorized(msg.sender).isAuthorized(offer.maker, signer), "invalid signature"
        );
        return CALLBACK_SUCCESS;
    }
}
