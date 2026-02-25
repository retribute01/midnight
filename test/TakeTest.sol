// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Obligation, Offer, Signature, Collateral} from "../src/interfaces/IMorphoV2.sol";
import {MorphoV2} from "../src/MorphoV2.sol";
import {WAD} from "../src/libraries/ConstantsLib.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {TickLib, TICK_RANGE} from "../src/libraries/TickLib.sol";
import {ICallbacks} from "../src/interfaces/ICallbacks.sol";
import {stdError} from "../lib/forge-std/src/StdError.sol";
import {BaseTest} from "./BaseTest.sol";
import {ERC20} from "./helpers/ERC20.sol";

contract TakeTest is BaseTest {
    using UtilsLib for uint256;

    Obligation internal obligation;
    bytes20 internal id;
    Offer internal lenderOffer;
    Offer internal borrowerOffer;
    Offer internal otherLenderOffer;
    Offer internal otherBorrowerOffer;

    uint256 internal maxAssets = 1e33; // to refine.
    uint256 internal initialUnits;
    uint256 internal initialShares;

    function setUp() public override {
        super.setUp();

        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 100;
        obligation.collaterals
            .push(Collateral({token: address(collateralToken1), lltv: 0.75e18, oracle: address(oracle1)}));
        obligation.collaterals
            .push(Collateral({token: address(collateralToken2), lltv: 0.75e18, oracle: address(oracle2)}));
        obligation.collaterals = sortCollaterals(obligation.collaterals);
        obligation.minCollatValue = 0;

        id = toId(obligation);

        lenderOffer.buy = true;
        lenderOffer.maker = lender;
        lenderOffer.obligationShares = type(uint256).max;
        lenderOffer.obligation = obligation;
        lenderOffer.expiry = block.timestamp + 200;
        lenderOffer.tick = TICK_RANGE;

        otherLenderOffer.buy = false;
        otherLenderOffer.maker = otherLender;
        otherLenderOffer.receiverIfMakerIsSeller = otherLender;
        otherLenderOffer.obligationShares = type(uint256).max;
        otherLenderOffer.obligation = obligation;
        otherLenderOffer.expiry = block.timestamp + 200;
        otherLenderOffer.tick = TICK_RANGE;

        borrowerOffer.buy = false;
        borrowerOffer.maker = borrower;
        borrowerOffer.receiverIfMakerIsSeller = borrower;
        borrowerOffer.obligationShares = type(uint256).max;
        borrowerOffer.obligation = obligation;
        borrowerOffer.expiry = block.timestamp + 200;
        borrowerOffer.tick = TICK_RANGE;

        otherBorrowerOffer.buy = true;
        otherBorrowerOffer.maker = otherBorrower;
        otherBorrowerOffer.obligationShares = type(uint256).max;
        otherBorrowerOffer.obligation = obligation;
        otherBorrowerOffer.expiry = block.timestamp + 200;
        otherBorrowerOffer.tick = TICK_RANGE;

        createBadDebt(obligation); // to create non trivial shares <=> units conversion.

        initialUnits = morphoV2.totalUnits(id);
        initialShares = morphoV2.totalShares(id);
    }

    // tests.

    // path 1: Lender enters + borrower enters.
    // obligationUnits = shares.mulDivUp(totalUnits+1, totalShares+1)

    function testBuyInput1(uint256 shares, uint256 tick) public {
        shares = bound(shares, 0, maxAssets);
        tick = bound(tick, 0, TICK_RANGE);
        uint256 price = TickLib.tickToPrice(tick);
        vm.assume(price > 0.01 ether);
        borrowerOffer.tick = tick;
        uint256 expectedUnits = shares.mulDivUp(initialUnits + 1, initialShares + 1);
        uint256 expectedBuyerAssets = expectedUnits.mulDivUp(price, WAD);
        uint256 expectedSellerAssets = expectedUnits.mulDivDown(price, WAD);
        deal(address(loanToken), lender, expectedBuyerAssets);
        collateralize(obligation, borrower, expectedUnits);

        take(shares, lender, borrowerOffer);

        assertEq(morphoV2.sharesOf(id, lender), shares, "lender shares");
        assertEq(morphoV2.debtOf(id, borrower), expectedUnits, "borrower debt");
        assertEq(morphoV2.totalUnits(id), initialUnits + expectedUnits, "total units");
        assertEq(morphoV2.totalShares(id), initialShares + shares, "total shares");
        assertEq(loanToken.balanceOf(borrower), expectedSellerAssets, "borrower balance");
        assertEq(loanToken.balanceOf(lender), 0, "lender balance");
        assertEq(morphoV2.consumed(borrower, 0), shares, "borrower consumed");
    }

    function testSellInput1(uint256 shares, uint256 tick) public {
        shares = bound(shares, 0, maxAssets);
        tick = bound(tick, 0, TICK_RANGE);
        uint256 price = TickLib.tickToPrice(tick);
        vm.assume(price > 0.01 ether);
        lenderOffer.tick = tick;
        uint256 expectedUnits = shares.mulDivUp(initialUnits + 1, initialShares + 1);
        uint256 expectedBuyerAssets = expectedUnits.mulDivUp(price, WAD);
        uint256 expectedSellerAssets = expectedUnits.mulDivDown(price, WAD);
        deal(address(loanToken), lender, expectedBuyerAssets);
        collateralize(obligation, borrower, expectedUnits);

        take(shares, borrower, lenderOffer);

        assertEq(morphoV2.sharesOf(id, lender), shares, "lender shares");
        assertEq(morphoV2.debtOf(id, borrower), expectedUnits, "borrower debt");
        assertEq(morphoV2.totalUnits(id), initialUnits + expectedUnits, "total units");
        assertEq(morphoV2.totalShares(id), initialShares + shares, "total shares");
        assertEq(loanToken.balanceOf(borrower), expectedSellerAssets, "borrower balance");
        assertEq(loanToken.balanceOf(lender), 0, "lender balance");
        assertEq(morphoV2.consumed(lender, 0), shares, "lender consumed");
    }

    // path 2: Lender enters + lender exits.
    // obligationUnits = shares.mulDivUp(totalUnits+1, totalShares+1)

    function testBuyInput2(uint256 shares, uint256 tick, uint256 otherLenderUnits) public {
        shares = bound(shares, 0, maxAssets);
        tick = bound(tick, 0, 600);
        uint256 price = TickLib.tickToPrice(tick);
        vm.assume(price > 0.01 ether);
        // We need otherLender to have enough shares.
        uint256 estimatedUnits = shares.mulDivUp(initialUnits + 1, initialShares + 1);
        otherLenderUnits = bound(otherLenderUnits, estimatedUnits, max(estimatedUnits, maxAssets));
        setupOtherUsers(obligation, otherLenderUnits);
        uint256 otherLenderShares = morphoV2.sharesOf(id, otherLender);
        vm.assume(shares <= otherLenderShares);
        // Read current totals after setupOtherUsers.
        uint256 currentTotalUnits = morphoV2.totalUnits(id);
        uint256 currentTotalShares = morphoV2.totalShares(id);
        // Path 2: lender enters + lender exits. Buyer (lender) pays buyerAssets.
        // otherLenderOffer.buy = false means: maker=otherLender is seller, taker=lender is buyer.
        uint256 obligationUnits = shares.mulDivUp(currentTotalUnits + 1, currentTotalShares + 1);
        uint256 buyerAssets = obligationUnits.mulDivUp(price, WAD);
        uint256 sellerAssets = obligationUnits.mulDivDown(price, WAD);
        deal(address(loanToken), lender, buyerAssets);
        uint256 otherLenderBalanceBefore = loanToken.balanceOf(otherLender);
        otherLenderOffer.buy = false;
        otherLenderOffer.obligationShares = type(uint256).max;
        otherLenderOffer.tick = tick;

        take(shares, lender, otherLenderOffer);

        assertApproxEqAbs(morphoV2.sharesOf(id, lender), shares, 1, "lender shares");
        assertApproxEqAbs(morphoV2.sharesOf(id, otherLender), otherLenderShares - shares, 1, "other lender shares");
        // Totals don't change for path 2.
        assertEq(morphoV2.totalUnits(id), currentTotalUnits, "total units");
        assertEq(morphoV2.totalShares(id), currentTotalShares, "total shares");
        // Buyer (lender) paid buyerAssets, seller (otherLender) received sellerAssets.
        assertEq(loanToken.balanceOf(lender), 0, "lender balance");
        assertApproxEqAbs(
            loanToken.balanceOf(otherLender), otherLenderBalanceBefore + sellerAssets, 1, "other lender balance"
        );
        assertEq(morphoV2.consumed(otherLenderOffer.maker, 0), shares, "maker consumed");
    }

    function testSellInput2(uint256 shares, uint256 tick, uint256 otherLenderUnits) public {
        shares = bound(shares, 0, maxAssets);
        tick = bound(tick, 0, 600);
        uint256 price = TickLib.tickToPrice(tick);
        vm.assume(price > 0.01 ether);
        uint256 estimatedUnits = shares.mulDivUp(initialUnits + 1, initialShares + 1);
        otherLenderUnits = bound(otherLenderUnits, estimatedUnits, max(estimatedUnits, maxAssets));
        setupOtherUsers(obligation, otherLenderUnits);
        uint256 otherLenderShares = morphoV2.sharesOf(id, otherLender);
        vm.assume(shares <= otherLenderShares);
        // Read current totals after setupOtherUsers.
        uint256 currentTotalUnits = morphoV2.totalUnits(id);
        uint256 currentTotalShares = morphoV2.totalShares(id);
        // Path 2: lender enters + lender exits. Buyer (lender) pays buyerAssets.
        // lenderOffer.buy = true means: maker=lender is buyer, taker=otherLender is seller.
        uint256 obligationUnits = shares.mulDivUp(currentTotalUnits + 1, currentTotalShares + 1);
        uint256 buyerAssets = obligationUnits.mulDivUp(price, WAD);
        uint256 sellerAssets = obligationUnits.mulDivDown(price, WAD);
        deal(address(loanToken), lender, buyerAssets);
        uint256 otherLenderBalanceBefore = loanToken.balanceOf(otherLender);
        lenderOffer.obligationShares = type(uint256).max;
        lenderOffer.tick = tick;

        take(shares, otherLender, lenderOffer);

        assertApproxEqAbs(morphoV2.sharesOf(id, lender), shares, 1, "lender shares");
        assertApproxEqAbs(morphoV2.sharesOf(id, otherLender), otherLenderShares - shares, 1, "other lender shares");
        assertEq(morphoV2.totalUnits(id), currentTotalUnits, "total units");
        assertEq(morphoV2.totalShares(id), currentTotalShares, "total shares");
        // Buyer (lender) paid buyerAssets, seller (otherLender) received sellerAssets.
        assertEq(loanToken.balanceOf(lender), 0, "lender balance");
        assertApproxEqAbs(
            loanToken.balanceOf(otherLender), otherLenderBalanceBefore + sellerAssets, 1, "other lender balance"
        );
        assertEq(morphoV2.consumed(lenderOffer.maker, 0), shares, "lender consumed");
    }

    function testCannotCrossTopDown(uint256 shares, uint256 otherLenderUnits) public {
        otherLenderUnits = bound(otherLenderUnits, 1, maxAssets - 1);
        setupOtherUsers(obligation, otherLenderUnits);
        uint256 otherLenderShares = morphoV2.sharesOf(id, otherLender);
        shares = bound(shares, otherLenderShares + 1, maxAssets);

        otherLenderOffer.obligationShares = type(uint256).max;
        vm.expectRevert(stdError.arithmeticError);
        take(shares, lender, otherLenderOffer);

        lenderOffer.obligationShares = type(uint256).max;
        vm.expectRevert(stdError.arithmeticError);
        take(shares, otherLender, lenderOffer);
    }

    // path 3: Borrower exits + borrower enters.
    // obligationUnits = shares.mulDivUp(totalUnits+1, totalShares+1) (same as path 1)

    function testBuyInput3(uint256 shares, uint256 tick, uint256 otherBorrowerDebt) public {
        shares = bound(shares, 0, maxAssets);
        tick = bound(tick, 0, 600);
        uint256 price = TickLib.tickToPrice(tick);
        vm.assume(price > 0.01 ether);
        // Need otherBorrower to have enough debt for the units derived from shares.
        // Path 3 uses mulDivUp, so we estimate generously.
        uint256 estimatedUnits = shares.mulDivUp(initialUnits + 1, initialShares + 1);
        otherBorrowerDebt = bound(otherBorrowerDebt, estimatedUnits, max(estimatedUnits, maxAssets));
        setupOtherUsers(obligation, otherBorrowerDebt);
        // Read current totals after setupOtherUsers.
        uint256 currentTotalUnits = morphoV2.totalUnits(id);
        uint256 currentTotalShares = morphoV2.totalShares(id);
        // Path 3: borrower exits + borrower enters. Uses mulDivUp.
        uint256 expectedUnits = shares.mulDivUp(currentTotalUnits + 1, currentTotalShares + 1);
        uint256 expectedBuyerAssets = expectedUnits.mulDivUp(price, WAD);
        uint256 expectedSellerAssets = expectedUnits.mulDivDown(price, WAD);
        // otherBorrower's actual debt from setupOtherUsers
        uint256 otherBorrowerActualDebt = morphoV2.debtOf(id, otherBorrower);
        vm.assume(expectedUnits <= otherBorrowerActualDebt);
        collateralize(obligation, borrower, expectedUnits);
        borrowerOffer.obligationShares = type(uint256).max;
        borrowerOffer.tick = tick;
        // otherBorrower got tokens from setupOtherUsers. Record balance before.
        uint256 otherBorrowerBalanceBefore = loanToken.balanceOf(otherBorrower);

        take(shares, otherBorrower, borrowerOffer);

        assertEq(morphoV2.debtOf(id, borrower), expectedUnits, "borrower debt");
        assertEq(morphoV2.debtOf(id, otherBorrower), otherBorrowerActualDebt - expectedUnits, "otherBorrower debt");
        // Totals don't change for path 3 (borrower exits + borrower enters).
        assertEq(morphoV2.totalUnits(id), currentTotalUnits, "total units");
        assertEq(morphoV2.totalShares(id), currentTotalShares, "total shares");
        assertEq(loanToken.balanceOf(borrower), expectedSellerAssets, "borrower balance");
        assertEq(
            loanToken.balanceOf(otherBorrower),
            otherBorrowerBalanceBefore - expectedBuyerAssets,
            "otherBorrower balance"
        );
        assertEq(morphoV2.consumed(borrowerOffer.maker, 0), shares, "maker consumed");
    }

    function testSellInput3(uint256 shares, uint256 tick, uint256 otherBorrowerDebt) public {
        shares = bound(shares, 0, maxAssets);
        tick = bound(tick, 0, 600);
        uint256 price = TickLib.tickToPrice(tick);
        vm.assume(price > 0.01 ether);
        uint256 estimatedUnits = shares.mulDivUp(initialUnits + 1, initialShares + 1);
        otherBorrowerDebt = bound(otherBorrowerDebt, estimatedUnits, max(estimatedUnits, maxAssets));
        setupOtherUsers(obligation, otherBorrowerDebt);
        // Read current totals after setupOtherUsers.
        uint256 currentTotalUnits = morphoV2.totalUnits(id);
        uint256 currentTotalShares = morphoV2.totalShares(id);
        // Path 3: borrower exits + borrower enters. Uses mulDivUp.
        uint256 expectedUnits = shares.mulDivUp(currentTotalUnits + 1, currentTotalShares + 1);
        uint256 expectedBuyerAssets = expectedUnits.mulDivUp(price, WAD);
        uint256 expectedSellerAssets = expectedUnits.mulDivDown(price, WAD);
        uint256 otherBorrowerActualDebt = morphoV2.debtOf(id, otherBorrower);
        vm.assume(expectedUnits <= otherBorrowerActualDebt);
        collateralize(obligation, borrower, expectedUnits);
        otherBorrowerOffer.obligationShares = type(uint256).max;
        otherBorrowerOffer.tick = tick;
        uint256 otherBorrowerBalanceBefore = loanToken.balanceOf(otherBorrower);

        take(shares, borrower, otherBorrowerOffer);

        assertEq(morphoV2.debtOf(id, borrower), expectedUnits, "borrower debt");
        assertEq(morphoV2.debtOf(id, otherBorrower), otherBorrowerActualDebt - expectedUnits, "otherBorrower debt");
        assertEq(morphoV2.totalUnits(id), currentTotalUnits, "total units");
        assertEq(morphoV2.totalShares(id), currentTotalShares, "total shares");
        assertEq(loanToken.balanceOf(borrower), expectedSellerAssets, "borrower balance");
        assertEq(
            loanToken.balanceOf(otherBorrower),
            otherBorrowerBalanceBefore - expectedBuyerAssets,
            "otherBorrower balance"
        );
        assertEq(morphoV2.consumed(otherBorrowerOffer.maker, 0), shares, "maker consumed");
    }

    function testCannotCrossBottomUp(uint256 shares, uint256 otherUnits) public {
        otherUnits = bound(otherUnits, 1, maxAssets - 1);
        setupOtherUsers(obligation, otherUnits);
        // otherBorrower has some debt. We need shares that would require more units than otherBorrower has.
        // Path 3 uses mulDivUp: units = shares * (totalUnits+1) / (totalShares+1), rounded up.
        // We need units > otherBorrower's debt. Use shares larger than totalShares to guarantee overflow.
        uint256 currentTotalShares = morphoV2.totalShares(id);
        shares = bound(shares, currentTotalShares + 1, max(currentTotalShares + 1, maxAssets));

        otherBorrowerOffer.obligationShares = type(uint256).max;
        vm.expectRevert(stdError.arithmeticError);
        take(shares, borrower, otherBorrowerOffer);

        borrowerOffer.obligationShares = type(uint256).max;
        vm.expectRevert(stdError.arithmeticError);
        take(shares, otherBorrower, borrowerOffer);
    }

    // path 4: Borrower exits + lender exits.
    // obligationUnits = shares.mulDivDown(totalUnits+1, totalShares+1)

    function testBuyInput4(uint256 shares, uint256 tick, uint256 existingUnits) public {
        shares = bound(shares, 0, maxAssets);
        tick = bound(tick, 0, 600);
        uint256 price = TickLib.tickToPrice(tick);
        vm.assume(price > 0.01 ether);
        uint256 estimatedUnits = shares.mulDivDown(initialUnits + 1, initialShares + 1);
        existingUnits = bound(existingUnits, estimatedUnits, max(estimatedUnits, maxAssets));
        setupOtherUsers(obligation, existingUnits);
        uint256 otherLenderShares = morphoV2.sharesOf(id, otherLender);
        vm.assume(shares <= otherLenderShares);
        // Read current totals after setupOtherUsers.
        uint256 currentTotalUnits = morphoV2.totalUnits(id);
        uint256 currentTotalShares = morphoV2.totalShares(id);
        // Path 4: borrower exits + lender exits. Uses mulDivDown.
        uint256 expectedUnits = shares.mulDivDown(currentTotalUnits + 1, currentTotalShares + 1);
        uint256 expectedBuyerAssets = expectedUnits.mulDivUp(price, WAD);
        uint256 expectedSellerAssets = expectedUnits.mulDivDown(price, WAD);
        uint256 otherBorrowerActualDebt = morphoV2.debtOf(id, otherBorrower);
        vm.assume(expectedUnits <= otherBorrowerActualDebt);
        uint256 otherBorrowerBalanceBefore = loanToken.balanceOf(otherBorrower);
        uint256 otherLenderBalanceBefore = loanToken.balanceOf(otherLender);
        otherLenderOffer.obligationShares = type(uint256).max;
        otherLenderOffer.tick = tick;

        take(shares, otherBorrower, otherLenderOffer);

        assertApproxEqAbs(morphoV2.sharesOf(id, otherLender), otherLenderShares - shares, 1, "otherLender shares");
        assertApproxEqAbs(
            morphoV2.debtOf(id, otherBorrower), otherBorrowerActualDebt - expectedUnits, 1, "otherBorrower debt"
        );
        assertApproxEqAbs(morphoV2.totalUnits(id), currentTotalUnits - expectedUnits, 1, "total units");
        assertApproxEqAbs(morphoV2.totalShares(id), currentTotalShares - shares, 1, "total shares");
        assertEq(
            loanToken.balanceOf(otherLender), otherLenderBalanceBefore + expectedSellerAssets, "otherLender balance"
        );
        assertEq(
            loanToken.balanceOf(otherBorrower),
            otherBorrowerBalanceBefore - expectedBuyerAssets,
            "otherBorrower balance"
        );
        assertEq(morphoV2.consumed(otherLenderOffer.maker, 0), shares, "maker consumed");
    }

    function testSellInput4(uint256 shares, uint256 tick, uint256 existingUnits) public {
        shares = bound(shares, 0, maxAssets);
        tick = bound(tick, 0, 600);
        uint256 price = TickLib.tickToPrice(tick);
        vm.assume(price > 0.01 ether);
        uint256 estimatedUnits = shares.mulDivDown(initialUnits + 1, initialShares + 1);
        existingUnits = bound(existingUnits, estimatedUnits, max(estimatedUnits, maxAssets));
        setupOtherUsers(obligation, existingUnits);
        uint256 otherLenderShares = morphoV2.sharesOf(id, otherLender);
        vm.assume(shares <= otherLenderShares);
        // Read current totals after setupOtherUsers.
        uint256 currentTotalUnits = morphoV2.totalUnits(id);
        uint256 currentTotalShares = morphoV2.totalShares(id);
        // Path 4: borrower exits + lender exits. Uses mulDivDown.
        uint256 expectedUnits = shares.mulDivDown(currentTotalUnits + 1, currentTotalShares + 1);
        uint256 expectedBuyerAssets = expectedUnits.mulDivUp(price, WAD);
        uint256 expectedSellerAssets = expectedUnits.mulDivDown(price, WAD);
        uint256 otherBorrowerActualDebt = morphoV2.debtOf(id, otherBorrower);
        vm.assume(expectedUnits <= otherBorrowerActualDebt);
        uint256 otherBorrowerBalanceBefore = loanToken.balanceOf(otherBorrower);
        uint256 otherLenderBalanceBefore = loanToken.balanceOf(otherLender);
        otherBorrowerOffer.obligationShares = type(uint256).max;
        otherBorrowerOffer.tick = tick;

        take(shares, otherLender, otherBorrowerOffer);

        assertApproxEqAbs(morphoV2.sharesOf(id, otherLender), otherLenderShares - shares, 1, "otherLender shares");
        assertApproxEqAbs(
            morphoV2.debtOf(id, otherBorrower), otherBorrowerActualDebt - expectedUnits, 1, "otherBorrower debt"
        );
        assertApproxEqAbs(morphoV2.totalUnits(id), currentTotalUnits - expectedUnits, 1, "total units");
        assertApproxEqAbs(morphoV2.totalShares(id), currentTotalShares - shares, 1, "total shares");
        assertEq(
            loanToken.balanceOf(otherLender), otherLenderBalanceBefore + expectedSellerAssets, "otherLender balance"
        );
        assertEq(
            loanToken.balanceOf(otherBorrower),
            otherBorrowerBalanceBefore - expectedBuyerAssets,
            "otherBorrower balance"
        );
        assertEq(morphoV2.consumed(otherBorrowerOffer.maker, 0), shares, "maker consumed");
    }

    // group tests.

    // with assets
    function testBuyConsumedSellerAssets(uint256 shares, uint256 offerAmount, uint256 secondTake) public {
        shares = bound(shares, 1, maxAssets - 1);
        uint256 price = TickLib.tickToPrice(TICK_RANGE);
        // Compute units and assets from shares for the first take (path 1: entering -> mulDivUp).
        uint256 units1 = shares.mulDivUp(initialUnits + 1, initialShares + 1);
        uint256 sellerAssets1 = units1.mulDivDown(price, WAD);
        vm.assume(sellerAssets1 > 0);
        offerAmount = bound(offerAmount, sellerAssets1, maxAssets - 1);
        secondTake = bound(secondTake, shares + 1, maxAssets);
        borrowerOffer.obligationShares = 0;
        borrowerOffer.sellerAssets = offerAmount;
        borrowerOffer.tick = TICK_RANGE;
        // Generous provisioning for both takes.
        uint256 maxUnitsTotal = offerAmount.mulDivUp(WAD, price) + 2;
        deal(address(loanToken), lender, offerAmount + maxUnitsTotal);
        collateralize(obligation, borrower, maxUnitsTotal + offerAmount);

        take(shares, lender, borrowerOffer);

        // Taking more than available should succeed but be capped.
        take(secondTake, lender, borrowerOffer);
    }

    function testSellConsumedBuyerAssets(uint256 shares, uint256 offerAmount, uint256 secondTake) public {
        shares = bound(shares, 1, maxAssets - 1);
        uint256 price = TickLib.tickToPrice(TICK_RANGE);
        uint256 units1 = shares.mulDivUp(initialUnits + 1, initialShares + 1);
        uint256 buyerAssets1 = units1.mulDivUp(price, WAD);
        vm.assume(buyerAssets1 > 0);
        offerAmount = bound(offerAmount, buyerAssets1, maxAssets - 1);
        secondTake = bound(secondTake, shares + 1, maxAssets);
        lenderOffer.obligationShares = 0;
        lenderOffer.buyerAssets = offerAmount;
        lenderOffer.tick = TICK_RANGE;
        uint256 maxUnitsTotal = offerAmount.mulDivUp(WAD, price) + 2;
        deal(address(loanToken), lender, offerAmount + maxUnitsTotal);
        collateralize(obligation, borrower, maxUnitsTotal + offerAmount);

        take(shares, borrower, lenderOffer);

        // Taking more than available should succeed but be capped.
        take(secondTake, borrower, lenderOffer);
    }

    function testBuyGroupSellerAssets(uint256 firstShares, uint256 secondShares) public {
        firstShares = bound(firstShares, 0, maxAssets);
        secondShares = bound(secondShares, 0, maxAssets);
        uint256 price = TickLib.tickToPrice(TICK_RANGE);
        // Compute sellerAssets for the total offer capacity.
        uint256 firstUnits = firstShares.mulDivUp(initialUnits + 1, initialShares + 1);
        uint256 firstSellerAssets = firstUnits.mulDivDown(price, WAD);
        uint256 secondUnits = secondShares.mulDivUp(initialUnits + 1, initialShares + 1);
        uint256 secondSellerAssets = secondUnits.mulDivDown(price, WAD);
        borrowerOffer.obligationShares = 0;
        borrowerOffer.sellerAssets = firstSellerAssets + secondSellerAssets;
        borrowerOffer.tick = TICK_RANGE;
        Offer memory borrowerOffer2 = borrowerOffer;
        borrowerOffer2.obligation.maturity = obligation.maturity + 100;
        // Generous provisioning.
        uint256 maxUnitsTotal = (firstSellerAssets + secondSellerAssets).mulDivUp(WAD, price) + 2;
        deal(address(loanToken), lender, firstSellerAssets + secondSellerAssets + maxUnitsTotal);
        collateralize(obligation, borrower, firstUnits + maxUnitsTotal);
        collateralize(borrowerOffer2.obligation, borrower, secondUnits + maxUnitsTotal);

        take(firstShares, lender, borrowerOffer);

        // Taking more than available should succeed but be capped.
        take(secondShares + maxUnitsTotal, lender, borrowerOffer2);
    }

    function testSellGroupBuyerAssets(uint256 firstShares, uint256 secondShares) public {
        firstShares = bound(firstShares, 0, maxAssets);
        secondShares = bound(secondShares, 0, maxAssets);
        uint256 price = TickLib.tickToPrice(TICK_RANGE);
        uint256 firstUnits = firstShares.mulDivUp(initialUnits + 1, initialShares + 1);
        uint256 firstBuyerAssets = firstUnits.mulDivUp(price, WAD);
        uint256 secondUnits = secondShares.mulDivUp(initialUnits + 1, initialShares + 1);
        uint256 secondBuyerAssets = secondUnits.mulDivUp(price, WAD);
        lenderOffer.obligationShares = 0;
        lenderOffer.buyerAssets = firstBuyerAssets + secondBuyerAssets;
        lenderOffer.tick = TICK_RANGE;
        Offer memory lenderOffer2 = lenderOffer;
        lenderOffer2.obligation.maturity = obligation.maturity + 100;
        uint256 maxUnitsTotal = (firstBuyerAssets + secondBuyerAssets).mulDivUp(WAD, price) + 2;
        deal(address(loanToken), lender, firstBuyerAssets + secondBuyerAssets + maxUnitsTotal);
        collateralize(obligation, borrower, firstUnits + maxUnitsTotal);
        collateralize(lenderOffer2.obligation, borrower, secondUnits + maxUnitsTotal);

        take(firstShares, borrower, lenderOffer);

        // Taking more than available should succeed but be capped.
        take(secondShares + maxUnitsTotal, borrower, lenderOffer2);
    }

    // with obligation units
    function testBuyConsumedUnits(uint256 shares, uint256 offerObligationUnits, uint256 secondTake) public {
        shares = bound(shares, 1, maxAssets - 1);
        uint256 units1 = shares.mulDivUp(initialUnits + 1, initialShares + 1);
        vm.assume(units1 > 0);
        offerObligationUnits = bound(offerObligationUnits, units1, maxAssets - 1);
        secondTake = bound(secondTake, shares + 1, maxAssets);
        borrowerOffer.obligationShares = 0;
        borrowerOffer.obligationUnits = offerObligationUnits;
        borrowerOffer.tick = TICK_RANGE;
        deal(address(loanToken), lender, offerObligationUnits + units1);
        collateralize(obligation, borrower, offerObligationUnits + units1);

        take(shares, lender, borrowerOffer);

        // Taking more than available should succeed but be capped.
        take(secondTake, lender, borrowerOffer);
    }

    function testSellConsumedUnits(uint256 shares, uint256 offerObligationUnits, uint256 secondTake) public {
        shares = bound(shares, 1, maxAssets - 1);
        uint256 units1 = shares.mulDivUp(initialUnits + 1, initialShares + 1);
        vm.assume(units1 > 0);
        offerObligationUnits = bound(offerObligationUnits, units1, maxAssets - 1);
        secondTake = bound(secondTake, shares + 1, maxAssets);
        lenderOffer.obligationShares = 0;
        lenderOffer.obligationUnits = offerObligationUnits;
        lenderOffer.tick = TICK_RANGE;
        deal(address(loanToken), lender, offerObligationUnits + units1);
        collateralize(obligation, borrower, offerObligationUnits + units1);

        take(shares, borrower, lenderOffer);

        // Taking more than available should succeed but be capped.
        take(secondTake, borrower, lenderOffer);
    }

    function testBuyGroupUnits(uint256 firstShares, uint256 secondShares) public {
        firstShares = bound(firstShares, 0, maxAssets);
        secondShares = bound(secondShares, 0, maxAssets);
        uint256 firstUnits = firstShares.mulDivUp(initialUnits + 1, initialShares + 1);
        uint256 secondUnits = secondShares.mulDivUp(initialUnits + 1, initialShares + 1);
        borrowerOffer.obligationShares = 0;
        borrowerOffer.obligationUnits = firstUnits + secondUnits;
        borrowerOffer.tick = TICK_RANGE;
        Offer memory borrowerOffer2 = borrowerOffer;
        borrowerOffer2.obligation.maturity = obligation.maturity + 100;
        deal(address(loanToken), lender, firstUnits + secondUnits + 2);
        collateralize(obligation, borrower, firstUnits + 2);
        collateralize(borrowerOffer2.obligation, borrower, secondUnits + 2);

        take(firstShares, lender, borrowerOffer);

        // Taking more than available should succeed but be capped.
        take(secondShares + 1, lender, borrowerOffer2);
    }

    function testSellGroupUnits(uint256 firstShares, uint256 secondShares) public {
        firstShares = bound(firstShares, 0, maxAssets);
        secondShares = bound(secondShares, 0, maxAssets);
        uint256 firstUnits = firstShares.mulDivUp(initialUnits + 1, initialShares + 1);
        uint256 secondUnits = secondShares.mulDivUp(initialUnits + 1, initialShares + 1);
        lenderOffer.obligationShares = 0;
        lenderOffer.obligationUnits = firstUnits + secondUnits;
        lenderOffer.tick = TICK_RANGE;
        Offer memory lenderOffer2 = lenderOffer;
        lenderOffer2.obligation.maturity = obligation.maturity + 100;
        deal(address(loanToken), lender, firstUnits + secondUnits + 2);
        collateralize(obligation, borrower, firstUnits + 2);
        collateralize(lenderOffer2.obligation, borrower, secondUnits + 2);

        take(firstShares, borrower, lenderOffer);

        // Taking more than available should succeed but be capped.
        take(secondShares + 1, borrower, lenderOffer2);
    }

    // with obligation shares
    function testBuyConsumedShares(uint256 shares1, uint256 offerObligationShares, uint256 secondTake) public {
        shares1 = bound(shares1, 1, maxAssets - 1);
        vm.assume(shares1 < maxAssets / 2);
        offerObligationShares = bound(offerObligationShares, shares1, maxAssets - 1);
        vm.assume(offerObligationShares < maxAssets / 2);
        secondTake = bound(secondTake, offerObligationShares - shares1 + 1, maxAssets);
        borrowerOffer.obligationShares = offerObligationShares;
        borrowerOffer.tick = TICK_RANGE;
        // Provide generous tokens and collateral for both takes.
        uint256 maxUnits = offerObligationShares.mulDivUp(initialUnits + 1, initialShares + 1) + 2;
        deal(address(loanToken), lender, maxUnits * 2);
        collateralize(obligation, borrower, maxUnits * 2);

        take(shares1, lender, borrowerOffer);

        // Taking more than available should succeed but be capped.
        take(secondTake, lender, borrowerOffer);
    }

    function testSellConsumedShares(uint256 shares1, uint256 offerObligationShares, uint256 secondTake) public {
        shares1 = bound(shares1, 1, maxAssets - 1);
        vm.assume(shares1 < maxAssets / 2);
        offerObligationShares = bound(offerObligationShares, shares1, maxAssets - 1);
        vm.assume(offerObligationShares < maxAssets / 2);
        secondTake = bound(secondTake, offerObligationShares - shares1 + 1, maxAssets);
        lenderOffer.obligationShares = offerObligationShares;
        lenderOffer.tick = TICK_RANGE;
        uint256 maxUnits = offerObligationShares.mulDivUp(initialUnits + 1, initialShares + 1) + 2;
        deal(address(loanToken), lender, maxUnits * 2);
        collateralize(obligation, borrower, maxUnits * 2);

        take(shares1, borrower, lenderOffer);

        // Taking more than available should succeed but be capped.
        take(secondTake, borrower, lenderOffer);
    }

    function testBuyGroupShares(uint256 firstShares, uint256 secondShares) public {
        firstShares = bound(firstShares, 1, maxAssets);
        secondShares = bound(secondShares, 1, maxAssets);
        vm.assume(firstShares + secondShares < maxAssets);
        uint256 price = TickLib.tickToPrice(TICK_RANGE);
        borrowerOffer.obligationShares = firstShares + secondShares;
        borrowerOffer.tick = TICK_RANGE;
        Offer memory borrowerOffer2 = borrowerOffer;
        borrowerOffer2.obligation.maturity = obligation.maturity + 100;
        // First take is on the bad debt market: units1 = firstShares * (initialUnits+1) / (initialShares+1) rounded up.
        uint256 units1 = firstShares.mulDivUp(initialUnits + 1, initialShares + 1);
        uint256 buyerAssets1 = units1.mulDivUp(price, WAD);
        // Second take is on a fresh market (totalUnits=0, totalShares=0): units2 = secondShares.
        uint256 units2 = secondShares;
        uint256 buyerAssets2 = units2.mulDivUp(price, WAD);
        deal(address(loanToken), lender, buyerAssets1 + buyerAssets2);
        collateralize(obligation, borrower, units1);
        collateralize(borrowerOffer2.obligation, borrower, units2);

        take(firstShares, lender, borrowerOffer);

        // Taking more than available should succeed but be capped.
        take(secondShares + units2, lender, borrowerOffer2);
    }

    function testSellGroupShares(uint256 firstShares, uint256 secondShares) public {
        firstShares = bound(firstShares, 1, maxAssets);
        secondShares = bound(secondShares, 1, maxAssets);
        vm.assume(firstShares + secondShares < maxAssets);
        uint256 price = TickLib.tickToPrice(TICK_RANGE);
        lenderOffer.obligationShares = firstShares + secondShares;
        lenderOffer.tick = TICK_RANGE;
        Offer memory lenderOffer2 = lenderOffer;
        lenderOffer2.obligation.maturity = obligation.maturity + 100;
        // First take is on the bad debt market: units1 = firstShares * (initialUnits+1) / (initialShares+1) rounded up.
        uint256 units1 = firstShares.mulDivUp(initialUnits + 1, initialShares + 1);
        uint256 buyerAssets1 = units1.mulDivUp(price, WAD);
        // Second take is on a fresh market (totalUnits=0, totalShares=0): units2 = secondShares.
        uint256 units2 = secondShares;
        uint256 buyerAssets2 = units2.mulDivUp(price, WAD);
        deal(address(loanToken), lender, buyerAssets1 + buyerAssets2);
        collateralize(obligation, borrower, units1);
        collateralize(lenderOffer2.obligation, borrower, units2);

        take(firstShares, borrower, lenderOffer);

        // Taking more than available should succeed but be capped.
        take(secondShares + units2, borrower, lenderOffer2);
    }

    // other tests.

    // address(this) makes an arbitrage for 2 crossed offers.
    function testMatch(uint256 shares1, uint256 tick1, uint256 tick2) public {
        shares1 = bound(shares1, 1, maxAssets);
        tick1 = bound(tick1, 600, TICK_RANGE);
        tick2 = bound(tick2, 600, TICK_RANGE);
        uint256 price1 = TickLib.tickToPrice(tick1);
        uint256 price2 = TickLib.tickToPrice(tick2);
        vm.assume(price1 > price2);
        vm.assume(price1 > 0.5 ether);
        vm.assume(price2 > 0.5 ether);
        // take1: address(this) buys from borrower at price1 (borrowerOffer.buy=false, taker=this is buyer).
        // Path 1: lender enters + borrower enters. Uses mulDivUp.
        uint256 units1 = shares1.mulDivUp(initialUnits + 1, initialShares + 1);
        uint256 buyerAssets1 = units1.mulDivUp(price1, WAD);
        uint256 sellerAssets1 = units1.mulDivDown(price1, WAD);
        vm.assume(units1 > 0);
        borrowerOffer.tick = tick1;
        lenderOffer.tick = tick2;

        deal(address(loanToken), address(this), buyerAssets1);
        collateralize(obligation, borrower, units1);

        take(shares1, address(this), borrowerOffer);

        // After take1: address(this) has shares1 shares, 0 debt, 0 balance.
        // take2: address(this) sells to lender at price2 (lenderOffer.buy=true, taker=this is seller).
        // buyerIsLender = true, sellerIsBorrower = false → Path 2: lender enters + lender exits.
        // Lender (buyer) needs buyerAssets2, receiver (this) gets sellerAssets2.
        uint256 postTake1TotalUnits = morphoV2.totalUnits(id);
        uint256 postTake1TotalShares = morphoV2.totalShares(id);
        uint256 units2 = shares1.mulDivUp(postTake1TotalUnits + 1, postTake1TotalShares + 1);
        uint256 buyerAssets2 = units2.mulDivUp(price2, WAD);
        uint256 sellerAssets2 = units2.mulDivDown(price2, WAD);
        deal(address(loanToken), lender, buyerAssets2);

        take(shares1, address(this), lenderOffer);

        // After take2: lender gets shares1 shares, this loses shares1 shares.
        assertEq(morphoV2.sharesOf(id, address(this)), 0, "shares");
        assertEq(morphoV2.debtOf(id, address(this)), 0, "debt");
        assertEq(morphoV2.sharesOf(id, lender), shares1, "lender shares");
        assertEq(morphoV2.debtOf(id, borrower), units1, "borrower debt");
        // address(this) received sellerAssets2 from take2.
        assertApproxEqAbs(loanToken.balanceOf(address(this)), sellerAssets2, 1, "balance");
        assertEq(loanToken.balanceOf(lender), 0, "lender balance");
        assertEq(loanToken.balanceOf(borrower), sellerAssets1, "borrower balance");
    }

    // address(this) makes an arbitrage for 2 crossed offers.
    function testMatchInverse(uint256 shares1, uint256 tick1, uint256 tick2) public {
        shares1 = bound(shares1, 1, maxAssets);
        tick1 = bound(tick1, 600, TICK_RANGE);
        tick2 = bound(tick2, 600, TICK_RANGE);
        uint256 price1 = TickLib.tickToPrice(tick1);
        uint256 price2 = TickLib.tickToPrice(tick2);
        vm.assume(price2 > price1);
        vm.assume(price1 > 0.5 ether);
        vm.assume(price2 > 0.5 ether);
        // take1: lender buys from `this` at price2 (lenderOffer.buy = true, taker = this is seller).
        // Path 1: lender enters + borrower enters. Uses mulDivUp.
        uint256 units1 = shares1.mulDivUp(initialUnits + 1, initialShares + 1);
        uint256 buyerAssets1 = units1.mulDivUp(price2, WAD);
        vm.assume(units1 > 0);
        borrowerOffer.tick = tick1;
        lenderOffer.tick = tick2;

        deal(address(loanToken), lender, buyerAssets1);
        collateralize(obligation, borrower, units1);
        collateralize(obligation, address(this), units1);

        // take1: lender buys from this (lenderOffer.buy = true). this is the seller.
        // this gets debt = units1, lender gets shares1.
        take(shares1, address(this), lenderOffer);

        // After take1: this has debt = units1, no shares. borrower has no debt, no shares.
        // take2: this buys from borrower (borrowerOffer.buy = false). this is the buyer.
        // this has debt > 0, borrower has no shares.
        // buyerIsLender = (this.debt == 0) = false, sellerIsBorrower = (borrower.shares == 0) = true.
        // Path 3: borrower exits + borrower enters. Uses mulDivUp.
        uint256 totalUnitsAfter1 = morphoV2.totalUnits(id);
        uint256 totalSharesAfter1 = morphoV2.totalShares(id);
        uint256 units2 = shares1.mulDivUp(totalUnitsAfter1 + 1, totalSharesAfter1 + 1);
        uint256 buyerAssets2 = units2.mulDivUp(price1, WAD);
        uint256 sellerAssets2 = units2.mulDivDown(price1, WAD);
        vm.assume(units2 <= units1);
        // Cover rounding: this received sellerAssets1, needs buyerAssets2. Deal extra if needed.
        uint256 thisBalanceBefore = loanToken.balanceOf(address(this));
        if (thisBalanceBefore < buyerAssets2) {
            deal(address(loanToken), address(this), buyerAssets2);
            thisBalanceBefore = buyerAssets2;
        }

        take(shares1, address(this), borrowerOffer);

        assertEq(morphoV2.sharesOf(id, address(this)), 0, "shares");
        assertEq(morphoV2.debtOf(id, address(this)), units1 - units2, "debt");
        assertEq(morphoV2.sharesOf(id, lender), shares1, "lender shares");
        assertEq(morphoV2.debtOf(id, borrower), units2, "borrower debt");
        assertEq(loanToken.balanceOf(address(this)), thisBalanceBefore - buyerAssets2, "balance");
        assertEq(loanToken.balanceOf(lender), 0, "lender balance");
        assertEq(loanToken.balanceOf(borrower), sellerAssets2, "borrower balance");
    }

    function testBuyPastMaturity(uint256 timestamp) public {
        timestamp = bound(timestamp, obligation.maturity, type(uint32).max);
        vm.warp(timestamp);
        borrowerOffer.expiry = timestamp;
        borrowerOffer.tick = TICK_RANGE;
        uint256 shares = 100;
        uint256 units = shares.mulDivUp(initialUnits + 1, initialShares + 1);
        uint256 buyerAssets = units.mulDivUp(TickLib.tickToPrice(TICK_RANGE), WAD);
        deal(address(loanToken), lender, buyerAssets);
        collateralize(obligation, borrower, units);

        take(shares, lender, borrowerOffer);
    }

    function testSellPastMaturity(uint256 timestamp) public {
        timestamp = bound(timestamp, obligation.maturity, type(uint32).max);
        vm.warp(timestamp);
        lenderOffer.expiry = timestamp;
        lenderOffer.tick = TICK_RANGE;
        uint256 shares = 100;
        uint256 units = shares.mulDivUp(initialUnits + 1, initialShares + 1);
        uint256 buyerAssets = units.mulDivUp(TickLib.tickToPrice(TICK_RANGE), WAD);
        deal(address(loanToken), lender, buyerAssets);
        collateralize(obligation, borrower, units);

        take(shares, borrower, lenderOffer);
    }

    function testBuyUnhealthy(uint256 shares, uint256 tick, uint256 collateralized) public {
        shares = bound(shares, 1, maxAssets);
        tick = bound(tick, 1, TICK_RANGE);
        uint256 price = TickLib.tickToPrice(tick);
        vm.assume(price > 0.01 ether);
        // Path 1: entering -> mulDivUp.
        uint256 expectedUnits = shares.mulDivUp(initialUnits + 1, initialShares + 1);
        vm.assume(expectedUnits > 0);
        uint256 expectedBuyerAssets = expectedUnits.mulDivUp(price, WAD);
        collateralized = bound(collateralized, 0, expectedUnits / 2);
        borrowerOffer.tick = tick;
        deal(address(loanToken), lender, expectedBuyerAssets);
        collateralize(obligation, borrower, collateralized);

        vm.expectRevert("Seller is unhealthy");
        take(shares, lender, borrowerOffer);
    }

    function testSellUnhealthy(uint256 shares, uint256 tick, uint256 collateralized) public {
        shares = bound(shares, 1, maxAssets);
        tick = bound(tick, 1, TICK_RANGE);
        uint256 price = TickLib.tickToPrice(tick);
        vm.assume(price > 0.01 ether);
        uint256 expectedUnits = shares.mulDivUp(initialUnits + 1, initialShares + 1);
        vm.assume(expectedUnits > 0);
        uint256 expectedBuyerAssets = expectedUnits.mulDivUp(price, WAD);
        collateralized = bound(collateralized, 0, expectedUnits / 2);
        lenderOffer.tick = tick;
        deal(address(loanToken), lender, expectedBuyerAssets);
        collateralize(obligation, borrower, collateralized);

        vm.expectRevert("Seller is unhealthy");
        take(shares, borrower, lenderOffer);
    }

    function testSession() public {
        vm.prank(lender);
        morphoV2.shuffleSession();

        vm.expectRevert("invalid session");
        take(100, borrower, lenderOffer);
    }

    // test tree / signatures.

    function testTakeWrongRoot() public {
        vm.expectRevert("invalid signature");
        vm.prank(borrower);
        morphoV2.take(
            100,
            borrower,
            address(0),
            hex"",
            borrower,
            lenderOffer,
            sig([borrowerOffer]),
            root([lenderOffer]),
            proof([lenderOffer])
        );
    }

    function testTakeInvalidSignature() public {
        vm.expectRevert("invalid signature");
        vm.prank(borrower);
        morphoV2.take(
            100,
            borrower,
            address(0),
            hex"",
            borrower,
            lenderOffer,
            Signature({v: 0, r: 0, s: 0}),
            root([lenderOffer]),
            proof([lenderOffer])
        );
    }

    function testTakeInvalidProofOneLeaf(bytes32[] memory proof) public {
        vm.assume(proof.length >= 1);
        vm.expectRevert("invalid proof");
        vm.prank(borrower);
        morphoV2.take(
            100, borrower, address(0), hex"", borrower, lenderOffer, sig([lenderOffer]), root([lenderOffer]), proof
        );
    }

    function testTakeInvalidProofTwoLeaves(Offer memory otherOffer, bytes32[] memory proof) public {
        vm.assume(proof.length >= 1);
        vm.assume(proof[0] != keccak256(abi.encode(otherOffer)));
        vm.expectRevert("invalid proof");
        vm.prank(borrower);
        morphoV2.take(
            100,
            borrower,
            address(0),
            hex"",
            borrower,
            lenderOffer,
            sig([lenderOffer, otherOffer]),
            root([lenderOffer, otherOffer]),
            proof
        );
    }

    function testTakeTwoLeaves(uint256 shares, Offer memory otherOffer) public {
        shares = bound(shares, 0, maxAssets);
        uint256 price = TickLib.tickToPrice(lenderOffer.tick);
        uint256 units = shares.mulDivUp(initialUnits + 1, initialShares + 1);
        uint256 buyerAssets = units.mulDivUp(price, WAD);
        deal(address(loanToken), lender, buyerAssets);
        collateralize(obligation, borrower, units);

        vm.prank(borrower);
        morphoV2.take(
            shares,
            borrower,
            address(0),
            hex"",
            borrower,
            lenderOffer,
            sig([lenderOffer, otherOffer]),
            root([lenderOffer, otherOffer]),
            proof([lenderOffer, otherOffer])
        );
    }

    // test callbacks.

    function testBuySellerCallback(uint256 shares) public {
        shares = bound(shares, 0, maxAssets);
        uint256 price = TickLib.tickToPrice(TICK_RANGE);
        uint256 units = shares.mulDivUp(initialUnits + 1, initialShares + 1);
        uint256 buyerAssets = units.mulDivUp(price, WAD);
        uint256 collateral = units.mulDivUp(WAD, obligation.collaterals[0].lltv);
        borrowerOffer.callback = address(new BorrowCallback());
        borrowerOffer.callbackData = abi.encode(0, collateral);
        borrowerOffer.tick = TICK_RANGE;
        deal(address(loanToken), lender, buyerAssets);
        deal(obligation.collaterals[0].token, borrowerOffer.callback, collateral);
        assertEq(morphoV2.collateralOf(id, borrower, 0), 0);

        take(shares, lender, borrowerOffer);

        assertEq(morphoV2.collateralOf(id, borrower, 0), collateral);
        assertEq(BorrowCallback(borrowerOffer.callback).recordedData(), borrowerOffer.callbackData);
    }

    function testSellSellerCallback(uint256 shares) public {
        shares = bound(shares, 0, maxAssets);
        uint256 price = TickLib.tickToPrice(TICK_RANGE);
        uint256 units = shares.mulDivUp(initialUnits + 1, initialShares + 1);
        uint256 buyerAssets = units.mulDivUp(price, WAD);
        uint256 collateral = units.mulDivUp(WAD, obligation.collaterals[0].lltv);
        lenderOffer.tick = TICK_RANGE;
        address callback = address(new BorrowCallback());
        deal(address(loanToken), lender, buyerAssets);
        deal(obligation.collaterals[0].token, callback, collateral);

        vm.prank(borrower);
        morphoV2.take(
            shares,
            borrower,
            callback,
            abi.encode(0, collateral),
            borrower,
            lenderOffer,
            sig([lenderOffer]),
            root([lenderOffer]),
            proof([lenderOffer])
        );
        assertEq(morphoV2.collateralOf(id, borrower, 0), collateral);
        assertEq(BorrowCallback(callback).recordedData(), abi.encode(0, collateral));
    }

    function testSellBuyerCallback(uint256 shares) public {
        shares = bound(shares, 0, maxAssets);
        uint256 price = TickLib.tickToPrice(TICK_RANGE);
        uint256 units = shares.mulDivUp(initialUnits + 1, initialShares + 1);
        uint256 buyerAssets = units.mulDivUp(price, WAD);
        lenderOffer.callback = address(new LendCallback());
        lenderOffer.callbackData = abi.encode(loanToken, buyerAssets);
        lenderOffer.maker = address(otherLender);
        lenderOffer.tick = TICK_RANGE;
        deal(address(loanToken), lenderOffer.callback, buyerAssets);
        collateralize(obligation, borrower, units);

        take(shares, borrower, lenderOffer);

        assertEq(LendCallback(lenderOffer.callback).recordedData(), lenderOffer.callbackData);
    }

    function testBuyBuyerCallback(uint256 shares) public {
        shares = bound(shares, 0, maxAssets);
        uint256 price = TickLib.tickToPrice(TICK_RANGE);
        uint256 units = shares.mulDivUp(initialUnits + 1, initialShares + 1);
        uint256 buyerAssets = units.mulDivUp(price, WAD);
        (address _otherLender,) = makeAddrAndKey("otherLender");
        vm.prank(_otherLender);
        loanToken.approve(address(morphoV2), buyerAssets);
        address callback = address(new LendCallback());
        borrowerOffer.tick = TICK_RANGE;
        deal(address(loanToken), callback, buyerAssets);
        collateralize(obligation, borrower, units);

        vm.prank(_otherLender);
        morphoV2.take(
            shares,
            _otherLender,
            callback,
            abi.encode(address(loanToken), buyerAssets),
            address(0),
            borrowerOffer,
            sig([borrowerOffer]),
            root([borrowerOffer]),
            proof([borrowerOffer])
        );
        assertEq(LendCallback(callback).recordedData(), abi.encode(address(loanToken), buyerAssets));
    }

    // Summary of zero price tests:
    //
    // No fee -> buyerPrice = 0 -> remainingShares computation for sellerAssets divides by 0. Reverts.
    // Fee > 0, buy offer -> sellerPrice = offerPrice - fee = 0 - fee -> underflow. Always reverts.
    // Fee > 0, sell offer -> sellerPrice = 0, buyerPrice = fee. Succeeds with sellerAssets = 0.

    function testPriceZero_NoTradingFee() public {
        // Use an offer with sellerAssets > 0 so the remainingShares computation divides by sellerPrice (= 0).
        borrowerOffer.tick = 0;
        borrowerOffer.obligationShares = 0;
        borrowerOffer.sellerAssets = 1e18;
        deal(address(loanToken), lender, 1e18);
        collateralize(obligation, borrower, 1e18);
        vm.expectRevert();
        take(100, lender, borrowerOffer);
    }

    function testPriceZero_WithTradingFee_buy() public {
        morphoV2.setObligationTradingFee(id, 0, 1e12);
        morphoV2.setObligationTradingFee(id, 1, 1e12);
        lenderOffer.tick = 0;
        uint256 shares = 100;
        uint256 units = shares.mulDivUp(initialUnits + 1, initialShares + 1);
        collateralize(obligation, borrower, units);
        vm.expectRevert();
        take(shares, borrower, lenderOffer);
    }

    function testPriceZero_WithTradingFee_sell() public {
        morphoV2.setObligationTradingFee(id, 0, 1e12);
        morphoV2.setObligationTradingFee(id, 1, 1e12);
        uint256 fee = morphoV2.tradingFee(id, obligation.maturity - block.timestamp);
        uint256 units = 1e18;
        uint256 shares = units.mulDivDown(initialShares + 1, initialUnits + 1);
        vm.assume(shares > 0);
        // Path 1: entering -> mulDivUp. Recompute units from shares.
        uint256 actualUnits = shares.mulDivUp(initialUnits + 1, initialShares + 1);
        uint256 expectedBuyerAssets = actualUnits.mulDivUp(fee, WAD);
        borrowerOffer.tick = 0;
        borrowerOffer.obligationShares = type(uint256).max;
        deal(address(loanToken), lender, expectedBuyerAssets);
        collateralize(obligation, borrower, actualUnits);
        (uint256 buyerAssets, uint256 sellerAssets,,) = take(shares, lender, borrowerOffer);
        assertEq(buyerAssets, expectedBuyerAssets, "buyerAssets");
        assertEq(sellerAssets, 0, "sellerAssets");
        assertEq(morphoV2.sharesOf(id, lender), shares, "sharesOf");
        assertEq(morphoV2.debtOf(id, borrower), actualUnits, "debtOf");
    }
}

contract BorrowCallback is ICallbacks {
    bytes public recordedData;

    function onSell(Obligation memory obligation, address seller, uint256, uint256, uint256, uint256, bytes memory data)
        external
    {
        recordedData = data;
        (uint256 collateralIndex, uint256 amount) = abi.decode(data, (uint256, uint256));
        address collateralToken = obligation.collaterals[collateralIndex].token;
        ERC20(collateralToken).approve(msg.sender, amount);
        MorphoV2(msg.sender).supplyCollateral(obligation, collateralIndex, amount, seller);
    }

    function onBuy(
        Obligation memory obligation,
        address buyer,
        uint256 buyerAssets,
        uint256 sellerAssets,
        uint256 obligationUnits,
        uint256 obligationShares,
        bytes memory data
    ) external {}

    function onLiquidate(Obligation memory, uint256, uint256, uint256, address, bytes memory) external {}
}

contract LendCallback is ICallbacks {
    bytes public recordedData;

    function onBuy(
        Obligation memory obligation,
        address buyer,
        uint256 buyerAssets,
        uint256,
        uint256,
        uint256,
        bytes memory data
    ) external {
        recordedData = data;
        require(ERC20(obligation.loanToken).transfer(buyer, buyerAssets), "transfer failed");
    }

    function onSell(
        Obligation memory obligation,
        address seller,
        uint256 buyerAssets,
        uint256 sellerAssets,
        uint256 obligationUnits,
        uint256 obligationShares,
        bytes memory data
    ) external {}

    function onLiquidate(Obligation memory, uint256, uint256, uint256, address, bytes memory) external {}
}
