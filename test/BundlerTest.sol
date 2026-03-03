// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Obligation, Offer, Signature, Collateral} from "../src/interfaces/IMidnight.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {TICK_RANGE} from "../src/libraries/TickLib.sol";
import {TakeBundler} from "../src/periphery/TakeBundler.sol";
import {BaseTest} from "./BaseTest.sol";

contract BundlerTest is BaseTest {
    using UtilsLib for uint256;

    TakeBundler internal takeBundler;

    Obligation internal obligation;
    bytes20 internal id;
    Offer[] internal offers;

    function setUp() public override {
        super.setUp();

        takeBundler = new TakeBundler();

        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 100;
        obligation.collaterals
            .push(Collateral({token: address(collateralToken1), lltv: 0.75e18, oracle: address(oracle1)}));
        obligation.collaterals
            .push(Collateral({token: address(collateralToken2), lltv: 0.75e18, oracle: address(oracle2)}));
        obligation.collaterals = sortCollaterals(obligation.collaterals);
        obligation.rcfThreshold = 0;

        id = toId(obligation);

        offers.push();
        offers[0].buy = true;
        offers[0].maker = lender;
        offers[0].obligationShares = 500;
        offers[0].obligation = obligation;
        offers[0].expiry = block.timestamp + 200;
        offers[0].tick = TICK_RANGE;

        offers.push();
        offers[1].buy = true;
        offers[1].maker = otherLender;
        offers[1].receiverIfMakerIsSeller = otherLender;
        offers[1].obligationShares = type(uint256).max;
        offers[1].obligation = obligation;
        offers[1].expiry = block.timestamp + 200;
        offers[1].tick = TICK_RANGE;

        deal(address(loanToken), lender, type(uint256).max);
        deal(address(loanToken), otherLender, type(uint256).max);
    }

    function testLengthMismatchSigs() public {
        Offer[] memory _offers = new Offer[](2);
        _offers[0] = offers[0];
        _offers[1] = offers[0];

        Signature[] memory sigs = new Signature[](1);
        bytes32[] memory roots = new bytes32[](2);
        bytes32[][] memory proofs = new bytes32[][](2);
        uint256[] memory _obligationShares = new uint256[](2);

        vm.prank(lender);
        vm.expectRevert("length mismatch");
        takeBundler.bundleTake(
            midnight, 100, lender, address(0), hex"", address(0), _obligationShares, _offers, sigs, roots, proofs
        );
    }

    function testLengthMismatchRoots() public {
        Offer[] memory _offers = new Offer[](2);
        _offers[0] = offers[0];
        _offers[1] = offers[0];

        Signature[] memory sigs = new Signature[](2);
        bytes32[] memory roots = new bytes32[](1);
        bytes32[][] memory proofs = new bytes32[][](2);
        uint256[] memory _obligationShares = new uint256[](2);

        vm.prank(lender);
        vm.expectRevert("length mismatch");
        takeBundler.bundleTake(
            midnight, 100, lender, address(0), hex"", address(0), _obligationShares, _offers, sigs, roots, proofs
        );
    }

    function testLengthMismatchProofs() public {
        Offer[] memory _offers = new Offer[](2);
        _offers[0] = offers[0];
        _offers[1] = offers[0];

        Signature[] memory sigs = new Signature[](2);
        bytes32[] memory roots = new bytes32[](2);
        bytes32[][] memory proofs = new bytes32[][](1);
        uint256[] memory _obligationShares = new uint256[](2);

        vm.prank(lender);
        vm.expectRevert("length mismatch");
        takeBundler.bundleTake(
            midnight, 100, lender, address(0), hex"", address(0), _obligationShares, _offers, sigs, roots, proofs
        );
    }

    function testBundler() public {
        Signature[] memory sigs = new Signature[](2);
        sigs[0] = sig([offers[0]]);
        sigs[1] = sig([offers[1]]);

        bytes32[] memory roots = new bytes32[](2);
        roots[0] = root([offers[0]]);
        roots[1] = root([offers[1]]);

        bytes32[][] memory proofs = new bytes32[][](2);
        proofs[0] = proof([offers[0]]);
        proofs[1] = proof([offers[1]]);

        uint256 units = 1000;
        uint256 shares = units;
        collateralize(obligation, borrower, units);

        uint256[] memory obligationShares = new uint256[](2);
        obligationShares[0] = offers[0].obligationShares;
        obligationShares[1] = offers[1].obligationShares;

        vm.prank(borrower);
        midnight.setIsAuthorized(address(takeBundler), true);

        vm.prank(borrower);
        midnight.setIsAuthorized(address(this), true);

        vm.prank(borrower);
        takeBundler.bundleTake(
            midnight, shares, borrower, address(0), hex"", address(0), obligationShares, offers, sigs, roots, proofs
        );

        assertEq(midnight.debtOf(id, borrower), units, "debt");
        assertEq(midnight.consumed(offers[0].maker, offers[0].group), 500, "consumed offer 0");
        assertEq(midnight.consumed(offers[1].maker, offers[1].group), 500, "consumed offer 1");
    }
}
