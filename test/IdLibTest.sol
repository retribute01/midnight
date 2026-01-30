// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {IdLib} from "../src/libraries/IdLib.sol";
import {Obligation} from "../src/interfaces/IMorphoV2.sol";

// idToObligation is tested in OtherFunctionsTest.sol, to test actual implementation (avoid introducing mocks).
contract IdLibTest is Test {
    function testToIdIsInjectiveInObligation(
        Obligation memory obligation1,
        Obligation memory obligation2,
        uint256 chainid,
        address morphoV2
    ) public pure {
        bool sameLoanToken = obligation1.loanToken == obligation2.loanToken;
        bool sameMaturity = obligation1.maturity == obligation2.maturity;
        bool sameCollaterals = obligation1.collaterals.length == obligation2.collaterals.length;
        if (sameCollaterals) {
            for (uint256 i = 0; i < obligation1.collaterals.length; i++) {
                if (obligation1.collaterals[i].token != obligation2.collaterals[i].token) sameCollaterals = false;
                if (obligation1.collaterals[i].lltv != obligation2.collaterals[i].lltv) sameCollaterals = false;
                if (obligation1.collaterals[i].oracle != obligation2.collaterals[i].oracle) sameCollaterals = false;
            }
        }
        vm.assume(!(sameLoanToken && sameMaturity && sameCollaterals));

        bytes32 id1 = IdLib.toId(obligation1, chainid, morphoV2);
        bytes32 id2 = IdLib.toId(obligation2, chainid, morphoV2);
        assertNotEq(id1, id2);
    }

    function testToIdIsInjectiveInChainId(
        Obligation memory obligation,
        uint256 chainid1,
        uint256 chainid2,
        address morphoV2
    ) public pure {
        vm.assume(chainid1 != chainid2);
        bytes32 id1 = IdLib.toId(obligation, chainid1, morphoV2);
        bytes32 id2 = IdLib.toId(obligation, chainid2, morphoV2);
        assertNotEq(id1, id2);
    }

    function testToIdIsInjectiveInMorphoV2(
        Obligation memory obligation,
        uint256 chainid,
        address morphoV2_1,
        address morphoV2_2
    ) public pure {
        vm.assume(morphoV2_1 != morphoV2_2);
        bytes32 id1 = IdLib.toId(obligation, chainid, morphoV2_1);
        bytes32 id2 = IdLib.toId(obligation, chainid, morphoV2_2);
        assertNotEq(id1, id2);
    }
}
