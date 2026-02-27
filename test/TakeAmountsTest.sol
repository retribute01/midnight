// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Obligation, Offer, Collateral} from "../src/interfaces/IMorphoV2.sol";
import {WAD} from "../src/libraries/ConstantsLib.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {TickLib, TICK_RANGE} from "../src/libraries/TickLib.sol";
import {BaseTest} from "./BaseTest.sol";
import {TakeAmountsLib} from "../src/periphery/TakeAmountsLib.sol";

contract TakeAmountsTest is BaseTest {
    using UtilsLib for uint256;

    Obligation internal obligation;
    bytes20 internal id;
    Offer internal lenderOffer;
    Offer internal borrowerOffer;

    function setUp() public override {
        super.setUp();

        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 100;
        obligation.collaterals
            .push(Collateral({token: address(collateralToken1), lltv: 0.75e18, oracle: address(oracle1)}));
        obligation.collaterals
            .push(Collateral({token: address(collateralToken2), lltv: 0.75e18, oracle: address(oracle2)}));
        obligation.collaterals = sortCollaterals(obligation.collaterals);
        obligation.rcfThreshold = 0;

        id = toId(obligation);

        lenderOffer.buy = true;
        lenderOffer.maker = lender;
        lenderOffer.obligationUnits = type(uint256).max;
        lenderOffer.obligation = obligation;
        lenderOffer.expiry = block.timestamp + 200;
        lenderOffer.tick = TICK_RANGE;

        borrowerOffer.buy = false;
        borrowerOffer.maker = borrower;
        borrowerOffer.receiverIfMakerIsSeller = borrower;
        borrowerOffer.obligationUnits = type(uint256).max;
        borrowerOffer.obligation = obligation;
        borrowerOffer.expiry = block.timestamp + 200;
        borrowerOffer.tick = TICK_RANGE;
    }

    // offer.buy = false: buyer = taker (lender), seller = maker (borrower).
    // sellerPrice = price, buyerPrice = price + fee.

    function testBuyerAssetsToUnitsSellOffer(uint256 targetBuyerAssets, uint256 tick, uint256 fee0, uint256 fee1)
        public
    {
        fee0 = bound(fee0, 0, morphoV2.maxTradingFee(0)) / 1e12 * 1e12;
        fee1 = bound(fee1, 0, morphoV2.maxTradingFee(1)) / 1e12 * 1e12;
        targetBuyerAssets = bound(targetBuyerAssets, 1, 1e30);
        tick = bound(tick, 1, TICK_RANGE);

        morphoV2.touchObligation(obligation);
        morphoV2.setObligationTradingFee(id, 0, fee0);
        morphoV2.setObligationTradingFee(id, 1, fee1);
        deal(address(loanToken), lender, type(uint256).max);
        borrowerOffer.tick = tick;
        // borrowerOffer.buy = false → buyerPrice = price + fee.
        uint256 buyerPrice = TickLib.tickToPrice(tick) + morphoV2.tradingFee(id, obligation.maturity - block.timestamp);
        vm.assume(buyerPrice <= WAD);
        uint256 units = TakeAmountsLib.buyerAssetsToUnits(targetBuyerAssets, buyerPrice);
        collateralize(obligation, borrower, units);

        (uint256 buyerAssets,,) = take(units, lender, borrowerOffer);

        assertEq(buyerAssets, targetBuyerAssets, "e2e buyerAssets");
    }

    function testSellerAssetsToUnitsSellOffer(uint256 targetSellerAssets, uint256 tick, uint256 fee0, uint256 fee1)
        public
    {
        fee0 = bound(fee0, 0, morphoV2.maxTradingFee(0)) / 1e12 * 1e12;
        fee1 = bound(fee1, 0, morphoV2.maxTradingFee(1)) / 1e12 * 1e12;
        targetSellerAssets = bound(targetSellerAssets, 1, 1e30);
        tick = bound(tick, 1, TICK_RANGE);

        morphoV2.touchObligation(obligation);
        morphoV2.setObligationTradingFee(id, 0, fee0);
        morphoV2.setObligationTradingFee(id, 1, fee1);
        vm.assume(TickLib.tickToPrice(tick) + morphoV2.tradingFee(id, obligation.maturity - block.timestamp) <= WAD);
        deal(address(loanToken), lender, type(uint256).max);
        borrowerOffer.tick = tick;
        // borrowerOffer.buy = false → sellerPrice = price.
        uint256 sellerPrice = TickLib.tickToPrice(tick);
        uint256 units = TakeAmountsLib.sellerAssetsToUnits(targetSellerAssets, sellerPrice);
        collateralize(obligation, borrower, units);

        (, uint256 sellerAssets,) = take(units, lender, borrowerOffer);

        assertEq(sellerAssets, targetSellerAssets, "e2e sellerAssets");
    }

    // offer.buy = true: buyer = maker (lender), seller = taker (borrower).
    // sellerPrice = offerPrice - fee, buyerPrice = offerPrice.

    function testBuyerAssetsToUnitsBuyOffer(uint256 targetBuyerAssets, uint256 tick, uint256 fee0, uint256 fee1)
        public
    {
        fee0 = bound(fee0, 0, morphoV2.maxTradingFee(0)) / 1e12 * 1e12;
        fee1 = bound(fee1, 0, morphoV2.maxTradingFee(1)) / 1e12 * 1e12;
        targetBuyerAssets = bound(targetBuyerAssets, 1, 1e30);
        tick = bound(tick, 1, TICK_RANGE);

        morphoV2.touchObligation(obligation);
        morphoV2.setObligationTradingFee(id, 0, fee0);
        morphoV2.setObligationTradingFee(id, 1, fee1);
        uint256 _tradingFee = morphoV2.tradingFee(id, obligation.maturity - block.timestamp);
        uint256 buyerPrice = TickLib.tickToPrice(tick);
        vm.assume(buyerPrice >= _tradingFee);
        deal(address(loanToken), lender, type(uint256).max);
        lenderOffer.tick = tick;
        uint256 units = TakeAmountsLib.buyerAssetsToUnits(targetBuyerAssets, buyerPrice);
        collateralize(obligation, borrower, units);

        (uint256 buyerAssets,,) = take(units, borrower, lenderOffer);

        assertEq(buyerAssets, targetBuyerAssets, "e2e buyerAssets");
    }

    function testSellerAssetsToUnitsBuyOffer(uint256 targetSellerAssets, uint256 tick, uint256 fee0, uint256 fee1)
        public
    {
        fee0 = bound(fee0, 0, morphoV2.maxTradingFee(0)) / 1e12 * 1e12;
        fee1 = bound(fee1, 0, morphoV2.maxTradingFee(1)) / 1e12 * 1e12;
        targetSellerAssets = bound(targetSellerAssets, 1, 1e30);
        tick = bound(tick, 1, TICK_RANGE);

        morphoV2.touchObligation(obligation);
        morphoV2.setObligationTradingFee(id, 0, fee0);
        morphoV2.setObligationTradingFee(id, 1, fee1);
        uint256 _tradingFee = morphoV2.tradingFee(id, obligation.maturity - block.timestamp);
        vm.assume(TickLib.tickToPrice(tick) > _tradingFee);
        deal(address(loanToken), lender, type(uint256).max);
        lenderOffer.tick = tick;
        uint256 sellerPrice = TickLib.tickToPrice(tick) - _tradingFee;
        // Ensure targetUnits = targetSellerAssets * WAD / sellerPrice fits in uint128.
        vm.assume(targetSellerAssets <= uint256(type(uint128).max).mulDivDown(sellerPrice, WAD));
        uint256 units = TakeAmountsLib.sellerAssetsToUnits(targetSellerAssets, sellerPrice);
        vm.assume(units <= type(uint128).max);
        vm.assume(units.mulDivUp(WAD, obligation.collaterals[0].lltv) <= type(uint128).max);
        collateralize(obligation, borrower, units);

        (, uint256 sellerAssets,) = take(units, borrower, lenderOffer);

        assertEq(sellerAssets, targetSellerAssets, "e2e sellerAssets");
    }
}
