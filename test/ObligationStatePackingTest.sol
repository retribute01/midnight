// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {Midnight} from "../src/Midnight.sol";
import {ERC20} from "./erc20s/ERC20.sol";
import {Oracle} from "./helpers/Oracle.sol";
import {Obligation, CollateralParams, ObligationState} from "../src/interfaces/IMidnight.sol";
import {LIQUIDATION_CURSOR_LOW, FEE_STEP} from "../src/libraries/ConstantsLib.sol";

contract ObligationStateHarness {
    mapping(bytes32 id => ObligationState) internal obligationState;

    function setCreated(bytes32 id, bool created) external {
        obligationState[id].created = created;
    }

    function setFee0(bytes32 id, uint16 fee) external {
        obligationState[id].fee0 = fee;
    }

    function setFee6(bytes32 id, uint16 fee) external {
        obligationState[id].fee6 = fee;
    }

    function setContinuousFee(bytes32 id, uint32 continuousFee) external {
        obligationState[id].continuousFee = continuousFee;
    }
}

contract ObligationStatePackingTest is Test {
    bytes32 internal constant ID = keccak256("obligation-id");
    uint256 internal constant OBLIGATION_STATE_MAPPING_SLOT = 0;

    Midnight internal midnight;
    ERC20 internal loanToken;
    ERC20 internal collateralToken;
    Oracle internal oracle;
    ObligationStateHarness internal harness;

    function setUp() public {
        midnight = new Midnight();
        midnight.setFeeSetter(address(this));
        loanToken = new ERC20("loan", "loan");
        collateralToken = new ERC20("collateral", "collateral");
        oracle = new Oracle();
        harness = new ObligationStateHarness();
    }

    function testPackedFieldsFitInThirdSlotOnly() public {
        bytes32 baseSlot = keccak256(abi.encode(ID, OBLIGATION_STATE_MAPPING_SLOT));

        harness.setCreated(ID, true);
        harness.setFee0(ID, 1);
        harness.setFee6(ID, 2);
        harness.setContinuousFee(ID, 3);

        assertEq(uint256(vm.load(address(harness), bytes32(uint256(baseSlot) + 0))), 0, "slot 0");
        assertEq(uint256(vm.load(address(harness), bytes32(uint256(baseSlot) + 1))), 0, "slot 1");
        assertTrue(uint256(vm.load(address(harness), bytes32(uint256(baseSlot) + 2))) > 0, "slot 2 should be used");
        assertEq(uint256(vm.load(address(harness), bytes32(uint256(baseSlot) + 3))), 0, "slot 3 should be empty");
        assertEq(uint256(vm.load(address(harness), bytes32(uint256(baseSlot) + 4))), 0, "slot 4 should be empty");
    }

    function testObligationStateGetterAndFeesGetter() public {
        for (uint256 i = 0; i < 7; ++i) {
            midnight.setDefaultTradingFee(address(loanToken), i, (i + 1) * FEE_STEP);
        }
        midnight.setDefaultContinuousFee(address(loanToken), 3);

        Obligation memory obligation;
        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 1 days;
        obligation.collateralParams = new CollateralParams[](1);
        obligation.collateralParams[0] = CollateralParams({
            token: address(collateralToken),
            lltv: 0.77e18,
            maxLif: midnight.maxLif(0.77e18, LIQUIDATION_CURSOR_LOW),
            oracle: address(oracle)
        });

        bytes32 id = midnight.touchObligation(obligation);

        (
            uint128 totalUnits,
            uint128 lossIndex,
            uint128 withdrawable,
            uint128 continuousFeeAmount,
            bool created,
            uint32 continuousFee
        ) = midnight.obligationState(id);
        uint16[7] memory fees = midnight.fees(id);

        assertEq(totalUnits, 0, "totalUnits");
        assertEq(lossIndex, 0, "lossIndex");
        assertEq(withdrawable, 0, "withdrawable");
        assertEq(continuousFeeAmount, 0, "continuousFeeAmount");
        assertEq(created, true, "created");
        assertEq(continuousFee, 3, "continuousFee");
        for (uint256 i = 0; i < 7; ++i) {
            assertEq(fees[i], i + 1, "fee");
        }
    }
}
