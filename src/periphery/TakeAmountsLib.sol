// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {UtilsLib} from "../libraries/UtilsLib.sol";
import {WAD} from "../libraries/ConstantsLib.sol";

library TakeAmountsLib {
    using UtilsLib for uint256;

    // Forward: buyerAssets = units.mulDivDown(buyerPrice, WAD).
    function buyerAssetsToUnits(uint256 targetBuyerAssets, uint256 buyerPrice) internal pure returns (uint256) {
        return targetBuyerAssets.mulDivUp(WAD, buyerPrice);
    }

    // Forward: sellerAssets = units.mulDivDown(sellerPrice, WAD).
    function sellerAssetsToUnits(uint256 targetSellerAssets, uint256 sellerPrice) internal pure returns (uint256) {
        return targetSellerAssets.mulDivUp(WAD, sellerPrice);
    }
}
