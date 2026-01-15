// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {BaseTest} from "./BaseTest.sol";
import {WAD} from "../src/libraries/ConstantsLib.sol";

contract SettersTest is BaseTest {
    function testInitialOwner() public view {
        assertEq(morphoV2.owner(), address(this), "deployer should be initial owner");
    }

    function testSetOwnerSuccess(address rdm) public {
        morphoV2.setOwner(rdm);
        assertEq(morphoV2.owner(), rdm, "owner should be transferred");
    }

    function testSetOwnerOnlyOwner(address rdm) public {
        vm.assume(rdm != address(this));
        vm.prank(rdm);
        vm.expectRevert("Only owner");
        morphoV2.setOwner(makeAddr("newOwner"));
    }

    function testSetFeeSetterSuccess(address feeSetter) public {
        morphoV2.setFeeSetter(feeSetter);
        assertEq(morphoV2.feeSetter(), feeSetter);
    }

    function testSetFeeSetterOnlyOwner(address rdm) public {
        vm.assume(rdm != address(this));
        vm.prank(rdm);
        vm.expectRevert("Only owner");
        morphoV2.setFeeSetter(makeAddr("newFeeSetter"));
    }

    function testSetTradingFeeSuccess(
        bytes32 id,
        uint256 zeroSecondsFee,
        uint256 oneDayFee,
        uint256 sevenDaysFee,
        uint256 thirtyDaysFee,
        uint256 ninetyDaysFee,
        uint256 oneEightyDaysFee
    ) public {
        zeroSecondsFee = bound(zeroSecondsFee, 0, WAD) / 1e12 * 1e12;
        oneDayFee = bound(oneDayFee, zeroSecondsFee, WAD) / 1e12 * 1e12;
        sevenDaysFee = bound(sevenDaysFee, oneDayFee, WAD) / 1e12 * 1e12;
        thirtyDaysFee = bound(thirtyDaysFee, sevenDaysFee, WAD) / 1e12 * 1e12;
        ninetyDaysFee = bound(ninetyDaysFee, thirtyDaysFee, WAD) / 1e12 * 1e12;
        oneEightyDaysFee = bound(oneEightyDaysFee, ninetyDaysFee, WAD) / 1e12 * 1e12;

        morphoV2.setObligationTradingFee(id, 0, zeroSecondsFee, true);
        morphoV2.setObligationTradingFee(id, 1, oneDayFee, true);
        morphoV2.setObligationTradingFee(id, 2, sevenDaysFee, true);
        morphoV2.setObligationTradingFee(id, 3, thirtyDaysFee, true);
        morphoV2.setObligationTradingFee(id, 4, ninetyDaysFee, true);
        morphoV2.setObligationTradingFee(id, 5, oneEightyDaysFee, true);

        assertEq(morphoV2.tradingFee(id, address(loanToken), 0), zeroSecondsFee, "zero days trading fee");
        assertEq(morphoV2.tradingFee(id, address(loanToken), 1 days), oneDayFee, "one day trading fee");
        assertEq(morphoV2.tradingFee(id, address(loanToken), 7 days), sevenDaysFee, "seven days trading fee");
        assertEq(morphoV2.tradingFee(id, address(loanToken), 30 days), thirtyDaysFee, "thirty days trading fee");
        assertEq(morphoV2.tradingFee(id, address(loanToken), 90 days), ninetyDaysFee, "ninety days trading fee");
        assertEq(morphoV2.tradingFee(id, address(loanToken), 180 days), oneEightyDaysFee, "one eighty days trading fee");
        assertEq(
            morphoV2.tradingFee(id, address(loanToken), 365 days), oneEightyDaysFee, "three sixty five days trading fee"
        );
        assertEq(
            morphoV2.tradingFee(id, address(loanToken), 1000 days), oneEightyDaysFee, "one thousand days trading fee"
        );
    }

    function testSetTradingFeeOnlyFeeSetter(address rdm, bytes32 id) public {
        vm.assume(rdm != address(this));
        vm.prank(rdm);
        vm.expectRevert("Only feeSetter");
        morphoV2.setObligationTradingFee(id, 0, 0, true);
    }

    function testSetTradingFeeZeroDaysTooHigh(bytes32 id, uint256 tradingFeeTooHigh) public {
        tradingFeeTooHigh = bound(tradingFeeTooHigh, WAD + 1, 2 * WAD);
        vm.expectRevert("Trading fee too high");
        morphoV2.setObligationTradingFee(id, 0, tradingFeeTooHigh, true);
    }

    function testSetTradingFeeRecipientSuccess(address recipient) public {
        morphoV2.setTradingFeeRecipient(recipient);
        assertEq(morphoV2.tradingFeeRecipient(), recipient, "recipient set");
    }

    function testSetTradingFeeRecipientOnlyOwner(address rdm) public {
        vm.assume(rdm != address(this));
        vm.prank(rdm);
        vm.expectRevert("Only owner");
        morphoV2.setTradingFeeRecipient(makeAddr("newRecipient"));
    }

    // Default trading fee tests

    function testUnsetDefaultFeeReturnsZero() public {
        address randomToken = makeAddr("randomToken");
        assertEq(morphoV2.tradingFee(bytes32(0), randomToken, 0), 0, "unset default fee should be 0");
        assertEq(morphoV2.tradingFee(bytes32(0), randomToken, 1 days), 0, "unset default fee should be 0");
        assertEq(morphoV2.tradingFee(bytes32(0), randomToken, 7 days), 0, "unset default fee should be 0");
        assertEq(morphoV2.tradingFee(bytes32(0), randomToken, 30 days), 0, "unset default fee should be 0");
        assertEq(morphoV2.tradingFee(bytes32(0), randomToken, 90 days), 0, "unset default fee should be 0");
    }

    function testSetDefaultTradingFeeSuccess(
        address loanToken,
        uint256 postMaturityFee,
        uint256 oneDayFee,
        uint256 sevenDaysFee,
        uint256 thirtyDaysFee,
        uint256 ninetyDaysFee,
        uint256 oneEightyDaysFee
    ) public {
        postMaturityFee = bound(postMaturityFee, 0, WAD) / 1e12 * 1e12;
        oneDayFee = bound(oneDayFee, postMaturityFee, WAD) / 1e12 * 1e12;
        sevenDaysFee = bound(sevenDaysFee, oneDayFee, WAD) / 1e12 * 1e12;
        thirtyDaysFee = bound(thirtyDaysFee, sevenDaysFee, WAD) / 1e12 * 1e12;
        ninetyDaysFee = bound(ninetyDaysFee, thirtyDaysFee, WAD) / 1e12 * 1e12;
        oneEightyDaysFee = bound(oneEightyDaysFee, ninetyDaysFee, WAD) / 1e12 * 1e12;

        morphoV2.setDefaultTradingFee(loanToken, 0, postMaturityFee, true);
        morphoV2.setDefaultTradingFee(loanToken, 1, oneDayFee, true);
        morphoV2.setDefaultTradingFee(loanToken, 2, sevenDaysFee, true);
        morphoV2.setDefaultTradingFee(loanToken, 3, thirtyDaysFee, true);
        morphoV2.setDefaultTradingFee(loanToken, 4, ninetyDaysFee, true);
        morphoV2.setDefaultTradingFee(loanToken, 5, oneEightyDaysFee, true);

        assertEq(morphoV2.tradingFee(bytes32(0), loanToken, 0), postMaturityFee, "0 days default fee");
        assertEq(morphoV2.tradingFee(bytes32(0), loanToken, 1 days), oneDayFee, "1 day default fee");
        assertEq(morphoV2.tradingFee(bytes32(0), loanToken, 7 days), sevenDaysFee, "7 days default fee");
        assertEq(morphoV2.tradingFee(bytes32(0), loanToken, 30 days), thirtyDaysFee, "30 days default fee");
        assertEq(morphoV2.tradingFee(bytes32(0), loanToken, 90 days), ninetyDaysFee, "90 days default fee");
        assertEq(morphoV2.tradingFee(bytes32(0), loanToken, 180 days), oneEightyDaysFee, "180 days default fee");
        assertEq(morphoV2.tradingFee(bytes32(0), loanToken, 365 days), oneEightyDaysFee, "365 days default fee");
        assertEq(morphoV2.tradingFee(bytes32(0), loanToken, 1000 days), oneEightyDaysFee, "1000 days default fee");
    }

    function testSetDefaultTradingFeeOnlyFeeSetter(address rdm, address loanToken) public {
        vm.assume(rdm != address(this));
        vm.prank(rdm);
        vm.expectRevert("Only feeSetter");
        morphoV2.setDefaultTradingFee(loanToken, 0, 0, true);
    }

    function testSetDefaultTradingFeeValidation(address loanToken, uint256 feeTooHigh) public {
        feeTooHigh = bound(feeTooHigh, WAD + 1, 2 * WAD);
        vm.expectRevert("Trading fee too high");
        morphoV2.setDefaultTradingFee(loanToken, 0, feeTooHigh, true);
    }

    function testDefaultTradingFeeTTMBuckets() public {
        address loanToken = makeAddr("loanToken");

        morphoV2.setDefaultTradingFee(loanToken, 0, 0.001e18, true);
        morphoV2.setDefaultTradingFee(loanToken, 1, 0.002e18, true);
        morphoV2.setDefaultTradingFee(loanToken, 2, 0.004e18, true);
        morphoV2.setDefaultTradingFee(loanToken, 3, 0.008e18, true);
        morphoV2.setDefaultTradingFee(loanToken, 4, 0.012e18, true);
        morphoV2.setDefaultTradingFee(loanToken, 5, 0.015e18, true);

        // Test breakpoint 0: 0 days (post maturity)
        assertEq(morphoV2.tradingFee(bytes32(0), loanToken, 0), 0.001e18, "0 days");

        // Test breakpoint 1: 1 day
        assertEq(morphoV2.tradingFee(bytes32(0), loanToken, 1 days), 0.002e18, "1 day");

        // Test breakpoint 2: 7 days
        assertEq(morphoV2.tradingFee(bytes32(0), loanToken, 7 days), 0.004e18, "7 days");

        // Test breakpoint 3: 30 days
        assertEq(morphoV2.tradingFee(bytes32(0), loanToken, 30 days), 0.008e18, "30 days");

        // Test breakpoint 4: 90 days
        assertEq(morphoV2.tradingFee(bytes32(0), loanToken, 90 days), 0.012e18, "90 days");

        // Test breakpoint 5: 180 days
        assertEq(morphoV2.tradingFee(bytes32(0), loanToken, 180 days), 0.015e18, "180 days");

        // Test beyond 180 days (should use breakpoint 5 fee)
        assertEq(morphoV2.tradingFee(bytes32(0), loanToken, 365 days), 0.015e18, "365 days");
        assertEq(morphoV2.tradingFee(bytes32(0), loanToken, 1000 days), 0.015e18, "1000 days");
    }

    function testLinearInterpolation() public {
        bytes32 id = keccak256("test");

        // Set fees at breakpoints: increasing curve
        morphoV2.setObligationTradingFee(id, 0, 0.01e18, true); // 0d: 1%
        morphoV2.setObligationTradingFee(id, 1, 0.02e18, true); // 1d: 2%
        morphoV2.setObligationTradingFee(id, 2, 0.04e18, true); // 7d: 4%
        morphoV2.setObligationTradingFee(id, 3, 0.08e18, true); // 30d: 8%
        morphoV2.setObligationTradingFee(id, 4, 0.12e18, true); // 90d: 12%
        morphoV2.setObligationTradingFee(id, 5, 0.15e18, true); // 180d: 15%

        // Test exact breakpoints
        assertEq(morphoV2.tradingFee(id, address(0), 0), 0.01e18, "0 days");
        assertEq(morphoV2.tradingFee(id, address(0), 1 days), 0.02e18, "1 day");
        assertEq(morphoV2.tradingFee(id, address(0), 7 days), 0.04e18, "7 days");
        assertEq(morphoV2.tradingFee(id, address(0), 30 days), 0.08e18, "30 days");
        assertEq(morphoV2.tradingFee(id, address(0), 90 days), 0.12e18, "90 days");
        assertEq(morphoV2.tradingFee(id, address(0), 180 days), 0.15e18, "180 days");

        // Test interpolation midpoints
        assertEq(morphoV2.tradingFee(id, address(0), 0.5 days), 0.015e18, "Midpoint 0-1d");
        assertEq(morphoV2.tradingFee(id, address(0), 4 days), 0.03e18, "Midpoint 1-7d");
        assertEq(morphoV2.tradingFee(id, address(0), 18.5 days), 0.06e18, "Midpoint 7-30d");
        assertEq(morphoV2.tradingFee(id, address(0), 60 days), 0.1e18, "Midpoint 30-90d");
        assertEq(morphoV2.tradingFee(id, address(0), 135 days), 0.135e18, "Midpoint 90-180d");

        // Test beyond 180 days
        assertEq(morphoV2.tradingFee(id, address(0), 365 days), 0.15e18, "365 days");
        assertEq(morphoV2.tradingFee(id, address(0), 1000 days), 0.15e18, "1000 days");
    }

    function testActivatedFlag() public {
        bytes32 id = keccak256("test");
        address token = makeAddr("token");

        // Set fee with activated = false, should return 0
        morphoV2.setObligationTradingFee(id, 1, 0.05e18, false);
        assertEq(morphoV2.tradingFee(id, token, 1 days), 0, "deactivated fee should be 0");

        // Activate the fee, should return the fee value
        morphoV2.setObligationTradingFee(id, 1, 0.05e18, true);
        assertEq(morphoV2.tradingFee(id, token, 1 days), 0.05e18, "activated fee should return value");

        // Deactivate, should return 0 again
        morphoV2.setObligationTradingFee(id, 1, 0.05e18, false);
        assertEq(morphoV2.tradingFee(id, token, 1 days), 0, "deactivated fee should be 0 again");
    }

    function testActivatedFlagFallbackToDefault() public {
        bytes32 id = keccak256("test");
        address token = makeAddr("token");

        // Set default fee as activated
        morphoV2.setDefaultTradingFee(token, 1, 0.02e18, true);

        // Obligation fee not activated, should fall back to default
        morphoV2.setObligationTradingFee(id, 1, 0.05e18, false);
        assertEq(morphoV2.tradingFee(id, token, 1 days), 0.02e18, "should fall back to default fee");

        // Activate obligation fee, should use obligation fee
        morphoV2.setObligationTradingFee(id, 1, 0.05e18, true);
        assertEq(morphoV2.tradingFee(id, token, 1 days), 0.05e18, "should use obligation fee");

        // Deactivate default fee too
        morphoV2.setDefaultTradingFee(token, 1, 0.02e18, false);
        morphoV2.setObligationTradingFee(id, 1, 0.05e18, false);
        assertEq(morphoV2.tradingFee(id, token, 1 days), 0, "both deactivated should return 0");
    }
}
