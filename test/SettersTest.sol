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
        uint256 oneSecondFee,
        uint256 oneDaysFee,
        uint256 twoDaysFee,
        uint256 fourDaysFee,
        uint256 eightDaysFee,
        uint256 sixteenDaysFee,
        uint256 thirtyTwoDaysFee,
        uint256 sixtyFourDaysFee
    ) public {
        zeroSecondsFee = bound(zeroSecondsFee, 0, WAD) / 1e12 * 1e12;
        oneSecondFee = bound(oneSecondFee, 0, WAD) / 1e12 * 1e12;
        oneDaysFee = bound(oneDaysFee, 0, WAD) / 1e12 * 1e12;
        twoDaysFee = bound(twoDaysFee, 0, WAD) / 1e12 * 1e12;
        fourDaysFee = bound(fourDaysFee, 0, WAD) / 1e12 * 1e12;
        eightDaysFee = bound(eightDaysFee, 0, WAD) / 1e12 * 1e12;
        sixteenDaysFee = bound(sixteenDaysFee, 0, WAD) / 1e12 * 1e12;
        thirtyTwoDaysFee = bound(thirtyTwoDaysFee, 0, WAD) / 1e12 * 1e12;
        sixtyFourDaysFee = bound(sixtyFourDaysFee, 0, WAD) / 1e12 * 1e12;

        morphoV2.setObligationTradingFee(id, 0, zeroSecondsFee);
        morphoV2.setObligationTradingFee(id, 1, oneSecondFee);
        morphoV2.setObligationTradingFee(id, 2, oneDaysFee);
        morphoV2.setObligationTradingFee(id, 3, twoDaysFee);
        morphoV2.setObligationTradingFee(id, 4, fourDaysFee);
        morphoV2.setObligationTradingFee(id, 5, eightDaysFee);
        morphoV2.setObligationTradingFee(id, 6, sixteenDaysFee);
        morphoV2.setObligationTradingFee(id, 7, thirtyTwoDaysFee);
        morphoV2.setObligationTradingFee(id, 8, sixtyFourDaysFee);

        assertEq(morphoV2.obligationTradingFee(id, 0), zeroSecondsFee, "zero seconds trading fee");
        assertEq(morphoV2.obligationTradingFee(id, 1), oneSecondFee, "one second trading fee");
        assertEq(morphoV2.obligationTradingFee(id, 1 days), oneDaysFee, "one days trading fee");
        assertEq(morphoV2.obligationTradingFee(id, 2 days), twoDaysFee, "two days trading fee");
        assertEq(morphoV2.obligationTradingFee(id, 4 days), fourDaysFee, "four days trading fee");
        assertEq(morphoV2.obligationTradingFee(id, 8 days), eightDaysFee, "eight days trading fee");
        assertEq(morphoV2.obligationTradingFee(id, 16 days), sixteenDaysFee, "sixteen days trading fee");
        assertEq(morphoV2.obligationTradingFee(id, 32 days), thirtyTwoDaysFee, "thirty two days trading fee");
        assertEq(morphoV2.obligationTradingFee(id, 64 days), sixtyFourDaysFee, "sixty four days trading fee");
        assertEq(
            morphoV2.obligationTradingFee(id, 128 days), sixtyFourDaysFee, "one hundred twenty eight days trading fee"
        );
        assertEq(
            morphoV2.obligationTradingFee(id, 256 days), sixtyFourDaysFee, "two hundred fifty six days trading fee"
        );
        assertEq(morphoV2.obligationTradingFee(id, 512 days), sixtyFourDaysFee, "five hundred twelve days trading fee");
        assertEq(
            morphoV2.obligationTradingFee(id, 1024 days), sixtyFourDaysFee, "one thousand twenty four days trading fee"
        );
        assertEq(
            morphoV2.obligationTradingFee(id, 2048 days), sixtyFourDaysFee, "two thousand forty eight days trading fee"
        );
        assertEq(
            morphoV2.obligationTradingFee(id, 4096 days), sixtyFourDaysFee, "four thousand ninety six days trading fee"
        );
    }

    function testSetTradingFeeOnlyFeeSetter(address rdm, bytes32 id) public {
        vm.assume(rdm != address(this));
        vm.prank(rdm);
        vm.expectRevert("Only feeSetter");
        morphoV2.setObligationTradingFee(id, 0, 0);
    }

    function testSetTradingFeeZeroDaysTooHigh(bytes32 id, uint256 tradingFeeTooHigh) public {
        tradingFeeTooHigh = bound(tradingFeeTooHigh, WAD + 1, 2 * WAD);
        vm.expectRevert("Trading fee too high");
        morphoV2.setObligationTradingFee(id, 0, tradingFeeTooHigh);
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
        assertEq(morphoV2.defaultTradingFee(randomToken, 0), 0, "unset default fee should be 0");
        assertEq(morphoV2.defaultTradingFee(randomToken, 1 days), 0, "unset default fee should be 0");
        assertEq(morphoV2.defaultTradingFee(randomToken, 7 days), 0, "unset default fee should be 0");
        assertEq(morphoV2.defaultTradingFee(randomToken, 30 days), 0, "unset default fee should be 0");
        assertEq(morphoV2.defaultTradingFee(randomToken, 90 days), 0, "unset default fee should be 0");
    }

    function testSetDefaultTradingFeeSuccess(
        address loanToken,
        uint256 postMaturityFee,
        uint256 oneSecondFee,
        uint256 oneDaysFee,
        uint256 twoDaysFee,
        uint256 fourDaysFee,
        uint256 eightDaysFee,
        uint256 sixteenDaysFee,
        uint256 thirtyTwoDaysFee,
        uint256 sixtyFourDaysFee
    ) public {
        postMaturityFee = bound(postMaturityFee, 0, WAD) / 1e12 * 1e12;
        oneSecondFee = bound(oneSecondFee, 0, WAD) / 1e12 * 1e12;
        oneDaysFee = bound(oneDaysFee, 0, WAD) / 1e12 * 1e12;
        twoDaysFee = bound(twoDaysFee, 0, WAD) / 1e12 * 1e12;
        fourDaysFee = bound(fourDaysFee, 0, WAD) / 1e12 * 1e12;
        eightDaysFee = bound(eightDaysFee, 0, WAD) / 1e12 * 1e12;
        sixteenDaysFee = bound(sixteenDaysFee, 0, WAD) / 1e12 * 1e12;
        thirtyTwoDaysFee = bound(thirtyTwoDaysFee, 0, WAD) / 1e12 * 1e12;
        sixtyFourDaysFee = bound(sixtyFourDaysFee, 0, WAD) / 1e12 * 1e12;

        morphoV2.setDefaultTradingFee(loanToken, 0, postMaturityFee);
        morphoV2.setDefaultTradingFee(loanToken, 1, oneSecondFee);
        morphoV2.setDefaultTradingFee(loanToken, 2, oneDaysFee);
        morphoV2.setDefaultTradingFee(loanToken, 3, twoDaysFee);
        morphoV2.setDefaultTradingFee(loanToken, 4, fourDaysFee);
        morphoV2.setDefaultTradingFee(loanToken, 5, eightDaysFee);
        morphoV2.setDefaultTradingFee(loanToken, 6, sixteenDaysFee);
        morphoV2.setDefaultTradingFee(loanToken, 7, thirtyTwoDaysFee);
        morphoV2.setDefaultTradingFee(loanToken, 8, sixtyFourDaysFee);

        assertEq(morphoV2.defaultTradingFee(loanToken, 0), postMaturityFee, "post maturity fee");
        assertEq(morphoV2.defaultTradingFee(loanToken, 1), oneSecondFee, "1 sec default fee");
        assertEq(morphoV2.defaultTradingFee(loanToken, 1 days), oneDaysFee, "1 day default fee");
        assertEq(morphoV2.defaultTradingFee(loanToken, 2 days), twoDaysFee, "2 days default fee");
        assertEq(morphoV2.defaultTradingFee(loanToken, 4 days), fourDaysFee, "4 days default fee");
        assertEq(morphoV2.defaultTradingFee(loanToken, 8 days), eightDaysFee, "8 days default fee");
        assertEq(morphoV2.defaultTradingFee(loanToken, 16 days), sixteenDaysFee, "16 days default fee");
        assertEq(morphoV2.defaultTradingFee(loanToken, 32 days), thirtyTwoDaysFee, "32 days default fee");
        assertEq(morphoV2.defaultTradingFee(loanToken, 64 days), sixtyFourDaysFee, "64 days default fee");
        assertEq(morphoV2.defaultTradingFee(loanToken, 128 days), sixtyFourDaysFee, "128 days default fee");
        assertEq(morphoV2.defaultTradingFee(loanToken, 256 days), sixtyFourDaysFee, "256 days default fee");
    }

    function testSetDefaultTradingFeeOnlyFeeSetter(address rdm, address loanToken) public {
        vm.assume(rdm != address(this));
        vm.prank(rdm);
        vm.expectRevert("Only feeSetter");
        morphoV2.setDefaultTradingFee(loanToken, 0, 0);
    }

    function testSetDefaultTradingFeeValidation(address loanToken, uint256 feeTooHigh) public {
        feeTooHigh = bound(feeTooHigh, WAD + 1, 2 * WAD);
        vm.expectRevert("Trading fee too high");
        morphoV2.setDefaultTradingFee(loanToken, 0, feeTooHigh);
    }

    function testDefaultTradingFeeTTMBuckets() public {
        address loanToken = makeAddr("loanToken");

        morphoV2.setDefaultTradingFee(loanToken, 0, 0.001e18);
        morphoV2.setDefaultTradingFee(loanToken, 1, 0.002e18);
        morphoV2.setDefaultTradingFee(loanToken, 2, 0.003e18);
        morphoV2.setDefaultTradingFee(loanToken, 3, 0.004e18);
        morphoV2.setDefaultTradingFee(loanToken, 4, 0.005e18);
        morphoV2.setDefaultTradingFee(loanToken, 5, 0.006e18);
        morphoV2.setDefaultTradingFee(loanToken, 6, 0.007e18);
        morphoV2.setDefaultTradingFee(loanToken, 7, 0.008e18);
        morphoV2.setDefaultTradingFee(loanToken, 8, 0.009e18);

        // Test bucket 0: post maturity
        assertEq(morphoV2.defaultTradingFee(loanToken, 0), 0.001e18, "0 seconds");

        // Test bucket 1: >= 1 second
        assertEq(morphoV2.defaultTradingFee(loanToken, 1), 0.002e18, "1 second");

        // Test bucket 2: >= 1 days
        assertEq(morphoV2.defaultTradingFee(loanToken, 1 days), 0.003e18, "1 day");

        // Test bucket 3: >= 2 days
        assertEq(morphoV2.defaultTradingFee(loanToken, 2 days), 0.004e18, "2 days");

        // Test bucket 4: >= 4 days
        assertEq(morphoV2.defaultTradingFee(loanToken, 4 days), 0.005e18, "4 days");

        // Test bucket 5: >= 8 days
        assertEq(morphoV2.defaultTradingFee(loanToken, 8 days), 0.006e18, "8 days");

        // Test bucket 6: >= 16 days
        assertEq(morphoV2.defaultTradingFee(loanToken, 16 days), 0.007e18, "16 days");

        // Test bucket 7: >= 32 days
        assertEq(morphoV2.defaultTradingFee(loanToken, 32 days), 0.008e18, "32 days");

        // Test bucket 8: >= 64 days
        assertEq(morphoV2.defaultTradingFee(loanToken, 64 days), 0.009e18, "64 days");
        assertEq(morphoV2.defaultTradingFee(loanToken, 128 days), 0.009e18, "128 days");
        assertEq(morphoV2.defaultTradingFee(loanToken, 256 days), 0.009e18, "256 days");
    }

    function testTradingFeeIndex() public view {
        assertEq(morphoV2.tradingFeeIndex(0), 0, "0 seconds");
        assertEq(morphoV2.tradingFeeIndex(1), 1, "1 second");
        assertEq(morphoV2.tradingFeeIndex(1 days - 1), 1, "1 day - 1 second");
        assertEq(morphoV2.tradingFeeIndex(1 days), 2, "1 day");
        assertEq(morphoV2.tradingFeeIndex(1 days + 1), 2, "1 day + 1 second");
        assertEq(morphoV2.tradingFeeIndex(2 days), 3, "2 days");
        assertEq(morphoV2.tradingFeeIndex(2 days + 1), 3, "2 days + 1 second");
        assertEq(morphoV2.tradingFeeIndex(4 days), 4, "4 days");
        assertEq(morphoV2.tradingFeeIndex(4 days + 1), 4, "4 days + 1 second");
        assertEq(morphoV2.tradingFeeIndex(8 days), 5, "8 days");
        assertEq(morphoV2.tradingFeeIndex(8 days + 1), 5, "8 days + 1 second");
        assertEq(morphoV2.tradingFeeIndex(16 days), 6, "16 days");
        assertEq(morphoV2.tradingFeeIndex(16 days + 1), 6, "16 days + 1 second");
        assertEq(morphoV2.tradingFeeIndex(32 days), 7, "32 days");
        assertEq(morphoV2.tradingFeeIndex(32 days + 1), 7, "32 days + 1 second");
        assertEq(morphoV2.tradingFeeIndex(64 days), 8, "64 days");
        assertEq(morphoV2.tradingFeeIndex(64 days + 1), 8, "64 days + 1 second");
        assertEq(morphoV2.tradingFeeIndex(128 days), 8, "128 days");
        assertEq(morphoV2.tradingFeeIndex(128 days + 1), 8, "128 days + 1 second");
        assertEq(morphoV2.tradingFeeIndex(256 days), 8, "256 days");
        assertEq(morphoV2.tradingFeeIndex(256 days + 1), 8, "256 days + 1 second");
        assertEq(morphoV2.tradingFeeIndex(512 days), 8, "512 days");
        assertEq(morphoV2.tradingFeeIndex(512 days + 1), 8, "512 days + 1 second");
        assertEq(morphoV2.tradingFeeIndex(1024 days), 8, "1024 days");
        assertEq(morphoV2.tradingFeeIndex(1024 days + 1), 8, "1024 days + 1 second");
        assertEq(morphoV2.tradingFeeIndex(2048 days), 8, "2048 days");
        assertEq(morphoV2.tradingFeeIndex(2048 days + 1), 8, "2048 days + 1 second");
        assertEq(morphoV2.tradingFeeIndex(4096 days), 8, "4096 days");
        assertEq(morphoV2.tradingFeeIndex(4096 days + 1), 8, "4096 days + 1 second");
        assertEq(morphoV2.tradingFeeIndex(8192 days), 8, "8192 days");
    }
}
