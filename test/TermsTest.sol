// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import "../src/Terms.sol";
import {ERC20} from "./helpers/ERC20.sol";
import {Oracle} from "./helpers/Oracle.sol";

contract TermsTest is Test {
    Terms private terms;
    ERC20 private loanToken;
    ERC20 private collateralToken;
    Oracle private oracle;

    function setUp() external {
        terms = new Terms();
        loanToken = new ERC20("loan", "loan", type(uint256).max);
        collateralToken = new ERC20("collat", "collat", type(uint256).max);
        oracle = new Oracle();
    }

    function testMint() external {
        Collateral[] memory collaterals = new Collateral[](1);
        collaterals[0] = Collateral({token: address(collateralToken), lltv: 1e18, oracle: address(oracle)});
        Offer memory lendOffer = Offer({
            lend: true,
            offering: address(this),
            assets: 100,
            loanToken: address(loanToken),
            collaterals: collaterals,
            maturity: block.timestamp + 100,
            price: 1
        });
        Offer memory borrowOffer = Offer({
            lend: false,
            offering: address(this),
            assets: 100,
            loanToken: address(loanToken),
            collaterals: collaterals,
            maturity: block.timestamp + 100,
            price: 1
        });

        Signature memory lendSig = Signature(0, 0, 0);
        Signature memory borrowSig = Signature(0, 0, 0);

        terms.mint(lendOffer, lendSig, borrowOffer, borrowSig);

        Term memory term = Term(address(loanToken), collaterals, block.timestamp + 100);
        bytes32 id = terms.id(term);

        assertEq(terms.bondOf(address(this), id), 100);
        assertEq(terms.debtOf(address(this), id), 100);
    }
}
