// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";

import "../src/Terms.sol";

abstract contract BaseTest is Test {
    Terms internal terms;

    function setUp() public virtual {
        terms = new Terms();
    }

    function _signOffer(Offer memory offer, uint256 sk) internal view returns (Signature memory) {
        bytes32 hashStruct = keccak256(abi.encode(terms.OFFER_TYPEHASH(), offer));
        bytes32 domainSeparator = keccak256(abi.encode(terms.DOMAIN_TYPEHASH(), block.chainid, address(terms)));
        bytes32 digest = keccak256(bytes.concat("\x19\x01", domainSeparator, hashStruct));

        Signature memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(sk, digest);
        return sig;
    }
}
