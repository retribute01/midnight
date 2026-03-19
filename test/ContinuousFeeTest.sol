// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {WAD, ORACLE_PRICE_SCALE, MAX_CONTINUOUS_FEE, PASSIVE_FEE_RECIPIENT} from "../src/libraries/ConstantsLib.sol";
import {EventsLib} from "../src/libraries/EventsLib.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {MAX_TICK} from "../src/libraries/TickLib.sol";
import {Obligation, Offer, Collateral} from "../src/interfaces/IMidnight.sol";
import {BaseTest, MAX_TEST_AMOUNT} from "./BaseTest.sol";

uint256 constant MAX_CREDIT = MAX_TEST_AMOUNT / 4;

contract ContinuousFeeTest is BaseTest {
    using UtilsLib for uint256;

    Obligation internal obligation;
    bytes32 internal id;
    Offer internal lenderOffer;
    address internal feeRecipient = makeAddr("feeRecipient");

    function setUp() public override {
        super.setUp();
        vm.warp(block.timestamp + 1000 days);

        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 100 days;
        obligation.collaterals
            .push(
                Collateral({
                    token: address(collateralToken1),
                    lltv: 0.75e18,
                    maxLif: maxLif(0.75e18, 0.25e18),
                    oracle: address(oracle1)
                })
            );
        obligation.rcfThreshold = 0;

        id = toId(obligation);
        midnight.setFeeRecipient(feeRecipient);

        lenderOffer.obligation = obligation;
        lenderOffer.buy = true;
        lenderOffer.maker = otherLender;
        lenderOffer.maxUnits = type(uint256).max;
        lenderOffer.expiry = block.timestamp;
        lenderOffer.tick = MAX_TICK;

        vm.prank(borrower);
        midnight.setIsAuthorized(borrower, address(this), true);
        vm.prank(otherBorrower);
        midnight.setIsAuthorized(otherBorrower, address(this), true);
    }

    /// @dev Sets up a lend + borrow position. After: lender.pendingFee = credit * feeRate * ttm / WAD,
    /// borrower.pendingFee = 0.
    function setupLender(uint256 credit, uint256 feeRate, uint256 ttm) internal {
        obligation.maturity = block.timestamp + ttm;
        id = toId(obligation);
        midnight.setDefaultContinuousFee(address(loanToken), feeRate);
        collateralize(obligation, borrower, credit * 2);
        setupObligation(obligation, credit);
    }

    function _makeLenderOffer(uint256 units, bytes32 group) internal returns (Offer memory o) {
        o.obligation = obligation;
        o.buy = true;
        o.maker = lender;
        o.maxUnits = units;
        o.expiry = block.timestamp;
        o.tick = MAX_TICK;
        o.group = group;
    }

    function _makeBuyOffer(uint256 units, bytes32 group) internal returns (Offer memory o) {
        o.obligation = obligation;
        o.buy = true;
        o.maker = otherLender;
        o.maxUnits = units;
        o.expiry = block.timestamp;
        o.tick = MAX_TICK;
        o.group = group;
    }

    function testAccrualPreMaturity(uint256 credit, uint256 feeRate, uint256 ttm, uint256 elapsed) public {
        credit = bound(credit, 1, MAX_CREDIT);
        feeRate = bound(feeRate, 0, MAX_CONTINUOUS_FEE);
        ttm = bound(ttm, 2, 360 days);
        elapsed = bound(elapsed, 1, ttm - 1);

        setupLender(credit, feeRate, ttm);
        uint256 remaining = midnight.pendingFee(id, lender);

        vm.warp(block.timestamp + elapsed);
        uint256 expectedFee = remaining.mulDivDown(elapsed, ttm);

        // Via withdraw(0)
        uint256 snap = vm.snapshotState();
        vm.expectEmit();
        emit EventsLib.AccrueContinuousFee(id, lender, expectedFee, remaining - expectedFee);
        vm.prank(lender);
        midnight.withdraw(obligation, 0, lender, lender);
        assertEq(midnight.creditOf(id, lender), credit - expectedFee, "credit after withdraw");
        assertEq(midnight.pendingFee(id, lender), remaining - expectedFee, "remaining after withdraw");
        vm.revertToState(snap);

        // Via direct call
        vm.expectEmit();
        emit EventsLib.AccrueContinuousFee(id, lender, expectedFee, remaining - expectedFee);
        midnight.accrueContinuousFee(obligation, lender);
        assertEq(midnight.creditOf(id, lender), credit - expectedFee, "credit after direct call");
        assertEq(midnight.pendingFee(id, lender), remaining - expectedFee, "remaining after direct call");
    }

    function testAccrualPreMaturityViaTake(uint256 credit, uint256 feeRate, uint256 ttm, uint256 elapsed) public {
        credit = bound(credit, 1, MAX_CREDIT);
        feeRate = bound(feeRate, 0, MAX_CONTINUOUS_FEE);
        ttm = bound(ttm, 2, 360 days);
        elapsed = bound(elapsed, 1, ttm - 1);

        setupLender(credit, feeRate, ttm);
        uint256 remaining = midnight.pendingFee(id, lender);

        vm.warp(block.timestamp + elapsed);
        uint256 expectedFee = remaining.mulDivDown(elapsed, ttm);

        // Via take (lender is maker, otherBorrower takes)
        deal(address(loanToken), lender, 1);
        collateralize(obligation, otherBorrower, 1);
        uint256 addedPending = uint256(feeRate).mulDivDown(ttm - elapsed, WAD);
        vm.expectEmit();
        emit EventsLib.AccrueContinuousFee(id, lender, expectedFee, remaining - expectedFee);
        vm.expectEmit();
        emit EventsLib.AccrueContinuousFee(id, otherBorrower, 0, 0);
        take(1, otherBorrower, _makeLenderOffer(1, keccak256("accrual-take")));
        assertApproxEqAbs(midnight.creditOf(id, lender), credit - expectedFee + 1, 1, "credit after take");
        assertApproxEqAbs(
            midnight.pendingFee(id, lender), remaining - expectedFee + addedPending, 1, "remaining after take"
        );
    }

    function testAccrualPostMaturity(uint256 credit, uint256 feeRate, uint256 ttm, uint256 extraTime) public {
        credit = bound(credit, 1, MAX_CREDIT);
        feeRate = bound(feeRate, 1, MAX_CONTINUOUS_FEE);
        ttm = bound(ttm, 1, 360 days);
        extraTime = bound(extraTime, 0, 360 days);

        setupLender(credit, feeRate, ttm);
        uint256 remaining = midnight.pendingFee(id, lender);
        vm.assume(remaining > 0);

        vm.warp(obligation.maturity + extraTime);

        // Via withdraw(0)
        uint256 snap = vm.snapshotState();
        vm.expectEmit();
        emit EventsLib.AccrueContinuousFee(id, lender, remaining, 0);
        vm.prank(lender);
        midnight.withdraw(obligation, 0, lender, lender);
        assertEq(midnight.creditOf(id, lender), credit - remaining, "all remaining consumed (withdraw)");
        assertEq(midnight.pendingFee(id, lender), 0, "remaining is zero (withdraw)");
        vm.revertToState(snap);

        // Via direct call
        vm.expectEmit();
        emit EventsLib.AccrueContinuousFee(id, lender, remaining, 0);
        midnight.accrueContinuousFee(obligation, lender);
        assertEq(midnight.creditOf(id, lender), credit - remaining, "all remaining consumed (direct)");
        assertEq(midnight.pendingFee(id, lender), 0, "remaining is zero (direct)");
    }

    function testMultipleAccrualsSumCorrectly(
        uint256 credit,
        uint256 feeRate,
        uint256 ttm,
        uint256 elapsed1,
        uint256 elapsed2
    ) public {
        credit = bound(credit, 1, MAX_CREDIT);
        feeRate = bound(feeRate, 1, MAX_CONTINUOUS_FEE);
        ttm = bound(ttm, 4, 360 days);
        elapsed1 = bound(elapsed1, 1, ttm / 2);
        elapsed2 = bound(elapsed2, 1, ttm / 2);

        setupLender(credit, feeRate, ttm);
        uint256 remaining = midnight.pendingFee(id, lender);
        vm.assume(remaining > 0);

        // Two separate accruals
        uint256 snap = vm.snapshotState();
        vm.warp(block.timestamp + elapsed1);
        midnight.accrueContinuousFee(obligation, lender);
        vm.warp(block.timestamp + elapsed2);
        midnight.accrueContinuousFee(obligation, lender);
        uint256 creditTwoAccruals = midnight.creditOf(id, lender);
        vm.revertToState(snap);

        // Single accrual for same total elapsed
        vm.warp(block.timestamp + elapsed1 + elapsed2);
        midnight.accrueContinuousFee(obligation, lender);
        uint256 creditOneAccrual = midnight.creditOf(id, lender);

        assertApproxEqAbs(creditTwoAccruals, creditOneAccrual, 2, "two accruals ~ one accrual");
    }

    function testSingleLend(uint256 credit, uint256 feeRate, uint256 ttm) public {
        credit = bound(credit, 1, MAX_CREDIT);
        feeRate = bound(feeRate, 0, MAX_CONTINUOUS_FEE);
        ttm = bound(ttm, 1, 360 days);

        setupLender(credit, feeRate, ttm);

        uint256 expectedRemaining = (uint256(feeRate) * credit).mulDivDown(ttm, WAD);
        assertEq(midnight.pendingFee(id, lender), expectedRemaining, "lender remaining after entry");
        assertEq(midnight.pendingFee(id, borrower), 0, "borrower has no pending fee");
        assertEq(midnight.debtOf(id, borrower), credit, "debt unchanged at entry");
    }

    function _makeBorrowOffer(uint256 credit2) internal returns (Offer memory borrowOffer) {
        borrowOffer.obligation = obligation;
        borrowOffer.buy = false;
        borrowOffer.maker = otherBorrower;
        borrowOffer.receiverIfMakerIsSeller = otherBorrower;
        borrowOffer.maxUnits = credit2;
        borrowOffer.start = block.timestamp;
        borrowOffer.expiry = block.timestamp;
        borrowOffer.tick = MAX_TICK;
    }

    function testTwoLendersDifferentRates(
        uint256 credit1,
        uint256 credit2,
        uint256 rate1,
        uint256 rate2,
        uint256 ttm,
        uint256 elapsed
    ) public {
        credit1 = bound(credit1, 1e18, MAX_CREDIT / 2);
        credit2 = bound(credit2, 1, MAX_CREDIT / 2);
        rate1 = bound(rate1, 0, MAX_CONTINUOUS_FEE);
        rate2 = bound(rate2, 0, MAX_CONTINUOUS_FEE);
        ttm = bound(ttm, 2, 360 days);
        elapsed = bound(elapsed, 1, ttm - 1);

        // First lend at rate1
        obligation.maturity = block.timestamp + ttm;
        id = toId(obligation);
        midnight.setDefaultContinuousFee(address(loanToken), rate1);
        collateralize(obligation, borrower, (credit1 + credit2) * 2);
        setupObligation(obligation, credit1);
        uint256 remaining1 = midnight.pendingFee(id, lender);

        // Change rate, lender adds more credit at rate2
        midnight.setObligationContinuousFee(id, rate2);
        collateralize(obligation, otherBorrower, credit2 * 2);
        deal(address(loanToken), lender, credit2);
        take(credit2, lender, _makeBorrowOffer(credit2));

        uint256 blendedRemaining = midnight.pendingFee(id, lender);
        uint256 expectedAdded = (uint256(rate2) * credit2).mulDivDown(ttm, WAD);
        assertApproxEqAbs(blendedRemaining, remaining1 + expectedAdded, 1, "remaining blended");

        // Accrue
        vm.warp(block.timestamp + elapsed);
        midnight.accrueContinuousFee(obligation, lender);

        uint256 expectedFee = blendedRemaining.mulDivDown(elapsed, ttm);
        assertApproxEqAbs(midnight.creditOf(id, lender), credit1 + credit2 - expectedFee, 1, "credit after accrual");
        assertApproxEqAbs(midnight.pendingFee(id, lender), blendedRemaining - expectedFee, 1, "remaining after accrual");
    }

    function testLendAtMaturity(uint256 credit, uint256 feeRate) public {
        credit = bound(credit, 1, MAX_CREDIT);
        feeRate = bound(feeRate, 1, MAX_CONTINUOUS_FEE);

        obligation.maturity = block.timestamp;
        id = toId(obligation);
        midnight.setDefaultContinuousFee(address(loanToken), feeRate);
        collateralize(obligation, borrower, credit * 2);
        setupObligation(obligation, credit);

        assertEq(midnight.pendingFee(id, lender), 0, "remaining is 0 at maturity");
    }

    function testExitViaLenderTake(uint256 credit, uint256 exitAmount, uint256 feeRate, uint256 ttm, uint256 elapsed)
        public
    {
        credit = bound(credit, 1, MAX_CREDIT);
        feeRate = bound(feeRate, 0, MAX_CONTINUOUS_FEE);
        ttm = bound(ttm, 2, 360 days);
        elapsed = bound(elapsed, 0, ttm - 1);

        setupLender(credit, feeRate, ttm);

        vm.warp(block.timestamp + elapsed);

        // Compute state after accrual
        uint256 remaining = midnight.pendingFee(id, lender);
        uint256 feeUnits = remaining.mulDivDown(elapsed, ttm);
        uint256 creditAfterAccrual = credit - feeUnits;
        uint256 remainingAfterAccrual = remaining - feeUnits;

        exitAmount = bound(exitAmount, 0, creditAfterAccrual);

        // Lender exits via take (lender is seller, otherLender is buyer)
        deal(address(loanToken), otherLender, exitAmount);

        vm.expectEmit();
        emit EventsLib.AccrueContinuousFee(id, otherLender, 0, 0);
        vm.expectEmit();
        emit EventsLib.AccrueContinuousFee(id, lender, feeUnits, remainingAfterAccrual);
        uint256 expectedRemaining = creditAfterAccrual > 0
            ? remainingAfterAccrual - remainingAfterAccrual.mulDivUp(exitAmount, creditAfterAccrual)
            : 0;
        take(exitAmount, lender, _makeBuyOffer(exitAmount, keccak256("lender-exit"))); // lender is taker = seller
        assertEq(midnight.creditOf(id, lender), creditAfterAccrual - exitAmount, "credit after exit");
        assertApproxEqAbs(midnight.pendingFee(id, lender), expectedRemaining, 1, "remaining after exit");

        if (exitAmount == creditAfterAccrual) {
            assertEq(midnight.pendingFee(id, lender), 0, "full exit zeroes remaining");
        }
    }

    function testWithdrawReducesPendingFee(
        uint256 credit,
        uint256 withdrawAmount,
        uint256 feeRate,
        uint256 ttm,
        uint256 elapsed
    ) public {
        credit = bound(credit, 1, MAX_CREDIT);
        feeRate = bound(feeRate, 0, MAX_CONTINUOUS_FEE);
        ttm = bound(ttm, 2, 360 days);
        elapsed = bound(elapsed, 0, ttm - 1);

        setupLender(credit, feeRate, ttm);

        vm.warp(block.timestamp + elapsed);

        uint256 remaining = midnight.pendingFee(id, lender);
        uint256 feeUnits = remaining.mulDivDown(elapsed, ttm);
        uint256 creditAfterAccrual = credit - feeUnits;
        uint256 remainingAfterAccrual = remaining - feeUnits;

        withdrawAmount = bound(withdrawAmount, 0, creditAfterAccrual);

        deal(address(loanToken), borrower, credit);
        vm.prank(borrower);
        midnight.repay(obligation, credit, borrower);

        vm.prank(lender);
        midnight.withdraw(obligation, withdrawAmount, lender, lender);

        uint256 expectedRemaining = creditAfterAccrual > 0
            ? remainingAfterAccrual - remainingAfterAccrual.mulDivUp(withdrawAmount, creditAfterAccrual)
            : 0;

        assertEq(midnight.creditOf(id, lender), creditAfterAccrual - withdrawAmount, "credit after withdraw");
        assertApproxEqAbs(midnight.pendingFee(id, lender), expectedRemaining, 1, "remaining after withdraw");

        if (withdrawAmount == creditAfterAccrual) {
            assertEq(midnight.pendingFee(id, lender), 0, "full withdraw zeroes remaining");
            midnight.accrueContinuousFee(obligation, lender);
            assertEq(midnight.pendingFee(id, lender), 0, "full withdraw stays at zero");
        }
    }

    function testExitViaLiquidation(uint256 debt, uint256 repaidUnits, uint256 feeRate, uint256 ttm, uint256 elapsed)
        public
    {
        debt = bound(debt, 1e18, MAX_CREDIT);
        feeRate = bound(feeRate, 0, MAX_CONTINUOUS_FEE);
        ttm = bound(ttm, 10, 360 days);
        elapsed = bound(elapsed, 1, ttm - 1);

        setupLender(debt, feeRate, ttm);

        // Make liquidatable
        oracle1.setPrice(ORACLE_PRICE_SCALE / 4);
        vm.warp(block.timestamp + elapsed);

        uint256 collateralAmount = midnight.collateralOf(id, borrower, 0);
        uint256 maxDebt = collateralAmount.mulDivDown(oracle1.price(), ORACLE_PRICE_SCALE)
            .mulDivDown(obligation.collaterals[0].lltv, WAD);
        uint256 lif = obligation.collaterals[0].maxLif;
        uint256 maxRepaid = (debt - maxDebt).mulDivUp(WAD, WAD - lif.mulDivUp(obligation.collaterals[0].lltv, WAD));
        uint256 collateralSafeRepaid =
            collateralAmount.mulDivDown(oracle1.price(), ORACLE_PRICE_SCALE).mulDivDown(WAD, lif);
        maxRepaid = UtilsLib.min(maxRepaid, collateralSafeRepaid);
        vm.assume(maxRepaid > 0);
        repaidUnits = bound(repaidUnits, 1, maxRepaid);

        deal(address(loanToken), address(this), repaidUnits);
        midnight.liquidate(obligation, 0, 0, repaidUnits, borrower, "");

        assertEq(midnight.pendingFee(id, borrower), 0, "borrower never has pending fee");
    }

    function testExitViaLiquidationBadDebtOnly(uint256 debt, uint256 feeRate, uint256 ttm, uint256 elapsed) public {
        debt = bound(debt, 1e18, MAX_CREDIT);
        feeRate = bound(feeRate, 0, MAX_CONTINUOUS_FEE);
        ttm = bound(ttm, 10, 360 days);
        elapsed = bound(elapsed, 1, ttm - 1);

        setupLender(debt, feeRate, ttm);

        // Make fully collateral-less (bad debt)
        oracle1.setPrice(0);
        vm.warp(block.timestamp + elapsed);

        midnight.liquidate(obligation, 0, 0, 0, borrower, "");

        assertEq(midnight.pendingFee(id, borrower), 0, "borrower never has pending fee");
    }

    function testAccrualAfterSlashReducesPendingFee(uint256 credit, uint256 feeRate, uint256 ttm, uint256 elapsed)
        public
    {
        credit = bound(credit, 100, MAX_CREDIT);
        feeRate = bound(feeRate, 1, MAX_CONTINUOUS_FEE);
        ttm = bound(ttm, 10, 360 days);
        elapsed = bound(elapsed, 1, ttm - 1);

        setupLender(credit, feeRate, ttm);
        vm.warp(block.timestamp + elapsed);

        uint256 pendingBeforeSlash = midnight.pendingFee(id, lender);

        createBadDebt(obligation);

        uint256 creditAfterSlash = midnight.creditAfterSlashing(id, lender);
        vm.assume(creditAfterSlash < credit);

        uint256 pendingAfterSlash = pendingBeforeSlash - pendingBeforeSlash.mulDivUp(credit - creditAfterSlash, credit);
        uint256 accruedFee = pendingAfterSlash.mulDivDown(elapsed, ttm);

        midnight.accrueContinuousFee(obligation, lender);

        assertEq(midnight.creditOf(id, lender), creditAfterSlash - accruedFee, "credit after slash and accrual");
        assertApproxEqAbs(
            midnight.pendingFee(id, lender), pendingAfterSlash - accruedFee, 1, "remaining after slash and accrual"
        );
    }

    function testFeeCreditMintedToRecipient(uint256 credit, uint256 feeRate, uint256 ttm, uint256 elapsed) public {
        credit = bound(credit, 1e18, MAX_CREDIT);
        feeRate = bound(feeRate, 1, MAX_CONTINUOUS_FEE);
        ttm = bound(ttm, 2, 360 days);
        elapsed = bound(elapsed, 1, ttm - 1);

        setupLender(credit, feeRate, ttm);
        uint256 remaining = midnight.pendingFee(id, lender);
        vm.assume(remaining > 0);

        vm.warp(block.timestamp + elapsed);
        midnight.accrueContinuousFee(obligation, lender);

        uint256 feeUnits = remaining.mulDivDown(elapsed, ttm);
        if (feeUnits > 0) {
            assertEq(midnight.creditOf(id, PASSIVE_FEE_RECIPIENT), feeUnits, "fee recipient credit");
        }
    }

    function testPerLenderRateLockIn(
        uint256 credit1,
        uint256 credit2,
        uint256 rate1,
        uint256 rate2,
        uint256 ttm,
        uint256 elapsed
    ) public {
        credit1 = bound(credit1, 1e18, MAX_CREDIT / 4);
        credit2 = bound(credit2, 1e18, MAX_CREDIT / 4);
        rate1 = bound(rate1, 1, MAX_CONTINUOUS_FEE);
        rate2 = bound(rate2, 1, MAX_CONTINUOUS_FEE);
        vm.assume(rate1 != rate2);
        ttm = bound(ttm, 2, 360 days);
        elapsed = bound(elapsed, 1, ttm - 1);

        _setupTwoLenders(credit1, credit2, rate1, rate2, ttm);

        vm.warp(block.timestamp + elapsed);

        uint256 fee1 = midnight.accrueContinuousFeeView(obligation, lender);
        uint256 fee2 = midnight.accrueContinuousFeeView(obligation, otherLender);
        midnight.accrueContinuousFee(obligation, lender);
        midnight.accrueContinuousFee(obligation, otherLender);

        assertEq(credit1 - midnight.creditOf(id, lender), fee1, "lender1 fee matches view");
        assertApproxEqAbs(fee1, (uint256(rate1) * credit1).mulDivDown(elapsed, WAD), 1, "lender1 fee from rate1");
        assertEq(credit2 - midnight.creditOf(id, otherLender), fee2, "lender2 fee matches view");
        assertApproxEqAbs(fee2, (uint256(rate2) * credit2).mulDivDown(elapsed, WAD), 1, "lender2 fee from rate2");
    }

    function _setupTwoLenders(uint256 credit1, uint256 credit2, uint256 rate1, uint256 rate2, uint256 ttm) internal {
        obligation.maturity = block.timestamp + ttm;
        id = toId(obligation);
        midnight.setDefaultContinuousFee(address(loanToken), rate1);
        collateralize(obligation, borrower, credit1 * 2);
        setupObligation(obligation, credit1);
        midnight.setObligationContinuousFee(id, rate2);
        collateralize(obligation, otherBorrower, credit2 * 2);
        setupOtherUsers(obligation, credit2);
    }

    function testSetContinuousFeeOnlyFeeSetter(address rdm) public {
        vm.assume(rdm != address(this));

        obligation.maturity = block.timestamp + 100 days;
        midnight.touchObligation(obligation);
        id = toId(obligation);

        vm.prank(rdm);
        vm.expectRevert("only fee setter");
        midnight.setObligationContinuousFee(id, 100);

        vm.prank(rdm);
        vm.expectRevert("only fee setter");
        midnight.setDefaultContinuousFee(address(loanToken), 100);
    }

    function testSetContinuousFeeTooHigh(uint256 fee) public {
        fee = bound(fee, MAX_CONTINUOUS_FEE + 1, type(uint256).max);

        obligation.maturity = block.timestamp + 100 days;
        midnight.touchObligation(obligation);
        id = toId(obligation);

        vm.expectRevert("continuous fee too high");
        midnight.setObligationContinuousFee(id, fee);

        vm.expectRevert("continuous fee too high");
        midnight.setDefaultContinuousFee(address(loanToken), fee);
    }

    function testSetContinuousFeeSuccess(uint256 fee) public {
        fee = bound(fee, 0, MAX_CONTINUOUS_FEE);

        midnight.setDefaultContinuousFee(address(loanToken), fee);
        assertEq(midnight.defaultContinuousFee(address(loanToken)), fee, "default fee updated");

        obligation.maturity = block.timestamp + 100 days;
        midnight.touchObligation(obligation);
        id = toId(obligation);

        midnight.setObligationContinuousFee(id, fee);
        assertEq(midnight.continuousFee(id), fee, "obligation fee updated");
    }

    function testFeeCreditRetrievableAfterRecipientChange(uint256 credit, uint256 feeRate, uint256 ttm, uint256 elapsed)
        public
    {
        credit = bound(credit, 1e18, MAX_CREDIT);
        feeRate = bound(feeRate, 1, MAX_CONTINUOUS_FEE);
        ttm = bound(ttm, 2, 360 days);
        elapsed = bound(elapsed, 1, ttm - 1);

        setupLender(credit, feeRate, ttm);
        uint256 remaining = midnight.pendingFee(id, lender);
        vm.assume(remaining > 0);

        // Accrue lender fee
        vm.warp(block.timestamp + elapsed);
        midnight.accrueContinuousFee(obligation, lender);
        uint256 feeCredit = midnight.creditOf(id, PASSIVE_FEE_RECIPIENT);
        vm.assume(feeCredit > 0);

        // Repay all borrower debt so withdrawable is filled
        uint256 totalDebt = midnight.debtOf(id, borrower);
        deal(address(loanToken), address(this), totalDebt);
        midnight.repay(obligation, totalDebt, borrower);

        // Change fee recipient
        address newRecipient = makeAddr("newFeeRecipient");
        midnight.setFeeRecipient(newRecipient);

        // New recipient can withdraw the fee credit
        vm.prank(newRecipient);
        midnight.withdraw(obligation, feeCredit, PASSIVE_FEE_RECIPIENT, newRecipient);

        assertEq(midnight.creditOf(id, PASSIVE_FEE_RECIPIENT), 0, "passive credit drained");
        assertEq(loanToken.balanceOf(newRecipient), feeCredit, "assets received");
    }

    function testRateChangeDoesNotAffectExistingLender(
        uint256 credit,
        uint256 rate1,
        uint256 rate2,
        uint256 ttm,
        uint256 elapsed
    ) public {
        credit = bound(credit, 1e18, MAX_CREDIT);
        rate1 = bound(rate1, 1, MAX_CONTINUOUS_FEE);
        rate2 = bound(rate2, 0, MAX_CONTINUOUS_FEE);
        vm.assume(rate1 != rate2);
        ttm = bound(ttm, 2, 360 days);
        elapsed = bound(elapsed, 1, ttm - 1);

        setupLender(credit, rate1, ttm);
        uint256 remaining = midnight.pendingFee(id, lender);

        midnight.setObligationContinuousFee(id, rate2);
        assertEq(midnight.pendingFee(id, lender), remaining, "remaining unchanged after rate change");

        vm.warp(block.timestamp + elapsed);
        midnight.accrueContinuousFee(obligation, lender);

        uint256 expectedFee = remaining.mulDivDown(elapsed, ttm);
        assertEq(midnight.creditOf(id, lender), credit - expectedFee, "fee from original rate");
        assertEq(midnight.pendingFee(id, lender), remaining - expectedFee, "remaining after accrual");
    }

    function testAccrualNearMaxCredit(uint256 credit, uint256 feeRate, uint256 ttm, uint256 elapsed) public {
        credit = bound(credit, MAX_TEST_AMOUNT / 2, MAX_TEST_AMOUNT * 9 / 10);
        feeRate = bound(feeRate, 1, MAX_CONTINUOUS_FEE);
        ttm = bound(ttm, 2, 3650 days);
        elapsed = bound(elapsed, 1, ttm - 1);

        obligation.collaterals[0].lltv = 1e18;
        obligation.collaterals[0].maxLif = maxLif(1e18, 0.25e18);
        obligation.maturity = block.timestamp + ttm;
        id = toId(obligation);
        midnight.setDefaultContinuousFee(address(loanToken), feeRate);
        collateralize(obligation, borrower, credit);
        setupObligation(obligation, credit);

        uint256 pending = midnight.pendingFee(id, lender);
        uint256 feeUnits = pending.mulDivDown(elapsed, ttm);

        vm.warp(block.timestamp + elapsed);

        midnight.accrueContinuousFee(obligation, lender);
        assertEq(midnight.creditOf(id, lender), credit - feeUnits, "credit after accrual");
    }
}
