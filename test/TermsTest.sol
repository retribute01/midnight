// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test, console} from "../lib/forge-std/src/Test.sol";
import "../src/Terms.sol";
import {ERC20} from "./helpers/ERC20.sol";
import {Oracle} from "./helpers/Oracle.sol";

contract TermsTest is Test {
    Terms private terms;
    ERC20 private loanToken;
    ERC20 private collateralToken;
    Oracle private oracle;
    address private borrower = makeAddr("borrower");
    Term private term;
    bytes32 private id;
    Collateral[] private collaterals;

    function setUp() external {
        terms = new Terms();
        loanToken = new ERC20("loan", "loan", 1 ether);
        collateralToken = new ERC20("collat", "collat", 1 ether);
        oracle = new Oracle();

        collaterals = new Collateral[](1);
        collaterals[0] = Collateral({token: address(collateralToken), lltv: 1e18, oracle: address(oracle)});

        term = Term(address(loanToken), collaterals, block.timestamp + 100);
        id = keccak256(abi.encode(term));

        loanToken.approve(address(terms), type(uint256).max);
        collateralToken.approve(address(terms), type(uint256).max);
        terms.supplyCollateral(term, address(collateralToken), 1 ether, borrower);
    }

    function testMint() external {
        Offer memory lendOffer = Offer({
            buy: true,
            offering: address(this),
            assets: 100,
            loanToken: address(loanToken),
            collaterals: collaterals,
            maturity: block.timestamp + 100,
            price: 1
        });
        Offer memory borrowOffer = Offer({
            buy: false,
            offering: borrower,
            assets: 100,
            loanToken: address(loanToken),
            collaterals: collaterals,
            maturity: block.timestamp + 100,
            price: 1
        });

        Signature memory lendSig = Signature(0, 0, 0);
        Signature memory borrowSig = Signature(0, 0, 0);

        terms.MATCH(lendOffer, lendSig, borrowOffer, borrowSig);

        assertEq(terms.bondOf(address(this), id), 100);
        assertEq(terms.debtOf(borrower, id), 100);

        assertEq(loanToken.balanceOf(borrower), 1);
    }
}
