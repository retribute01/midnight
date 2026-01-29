// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {WAD, TICK_RANGE} from "../src/libraries/ConstantsLib.sol";

contract TickTest is Test {
    using UtilsLib for uint256;

    // Tick to price

    function testTickToPriceMinMax() public pure {
        assertEq(UtilsLib.tickToPrice(0), 0.00001e18, "tick 0");
        assertEq(UtilsLib.tickToPrice(TICK_RANGE - 1), 0.99999e18, "tick max - 1");
        assertEq(UtilsLib.tickToPrice(TICK_RANGE), WAD, "tick max");
    }

    function testTickMonotonicity() public pure {
        for (uint256 i = 0; i < TICK_RANGE; i++) {
            assertGe(UtilsLib.tickToPrice(i + 1), UtilsLib.tickToPrice(i));
        }
    }

    function testTickToPriceRange() public pure {
        for (uint256 i = 0; i <= TICK_RANGE; i++) {
            console.log(UtilsLib.tickToPrice(i));
        }
    }

    function testReturnJumps() public pure {
        uint256 price = UtilsLib.tickToPrice(200);
        uint256 previousReturn = _return(price);
        for (uint256 i = 200; i <= 700; i++) {
            uint256 currentReturn = _return(UtilsLib.tickToPrice(i));
            assertApproxEqRel(currentReturn, previousReturn.mulDivDown(WAD, 1.025e18), 0.05e18, "tick i");
            previousReturn = currentReturn;
        }
    }

    function _return(uint256 price) internal pure returns (uint256) {
        return WAD.mulDivDown(WAD, price) - WAD;
    }

    // Price to tick

    function testPriceToTick(uint256 price) public pure {
        price = bound(price, 0, 1 ether);
        uint256 tick = UtilsLib.priceToTick(price);
        assertGe(UtilsLib.tickToPrice(tick), price);
        if (tick > 0) assertLe(UtilsLib.tickToPrice(tick - 1), price);
    }

    function testPriceToTickConsistency() public pure {
        for (uint256 tick = 0; tick <= TICK_RANGE; tick++) {
            uint256 price = UtilsLib.tickToPrice(tick);
            uint256 recovered = UtilsLib.priceToTick(price);
            assertEq(UtilsLib.tickToPrice(recovered), price, "price mismatch");
            assertLe(recovered, tick, "recovered > tick");
        }
    }
}
