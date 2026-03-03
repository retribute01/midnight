// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.31;

import {Midnight} from "../Midnight.sol";
import {Offer, Signature} from "../interfaces/IMidnight.sol";
import {UtilsLib} from "../libraries/UtilsLib.sol";
import {TakeAmountsLib} from "./TakeAmountsLib.sol";

contract TakeBundler {
    using UtilsLib for uint256;

    struct Take {
        Offer offer;
        uint256 obligationShares;
        Signature sig;
        bytes32 root;
        bytes32[] proof;
    }

    /// @dev Iterates through orders, filling up to `targetShares` obligation shares total.
    /// @dev Assumes all offers share the same obligation id so that obligation shares are comparable.
    /// @dev The taker must have authorized this bundler and the msg.sender (if different from the taker) on Midnight.
    /// @dev The bundler skips every reason why `take` can revert (including ones that are not asynchrony related).
    /// @dev If taking an offer reverts, the bundler will completely skip this offer.
    function bundleTakeShares(
        Midnight midnight,
        uint256 targetShares,
        address taker,
        address receiverIfTakerIsSeller,
        Take[] calldata takes
    ) external {
        require(taker == msg.sender || midnight.isAuthorized(taker, msg.sender), "UNAUTHORIZED");

        uint256 totalFilledShares;
        for (uint256 i; i < takes.length && totalFilledShares < targetShares; i++) {
            Take calldata take_ = takes[i];
            try midnight.take(
                UtilsLib.min(targetShares - totalFilledShares, take_.obligationShares),
                taker,
                address(0),
                "",
                receiverIfTakerIsSeller,
                take_.offer,
                take_.sig,
                take_.root,
                take_.proof
            ) returns (
                uint256, uint256, uint256, uint256 filledShares
            ) {
                totalFilledShares += filledShares;
            } catch {}
        }

        require(totalFilledShares == targetShares, "insufficient liquidity");
    }

    /// @dev Same as bundleTakeShares but targets obligation units.
    function bundleTakeUnits(
        Midnight midnight,
        uint256 targetUnits,
        address taker,
        address receiverIfTakerIsSeller,
        Take[] calldata takes
    ) external {
        require(taker == msg.sender || midnight.isAuthorized(taker, msg.sender), "UNAUTHORIZED");
        require(takes.length != 0, "empty takes");
        bytes20 id = midnight.toId(takes[0].offer.obligation);

        uint256 totalFilledUnits;
        for (uint256 i; i < takes.length && totalFilledUnits < targetUnits; i++) {
            Take calldata take_ = takes[i];
            try midnight.take(
                UtilsLib.min(
                    TakeAmountsLib.unitsToShares(midnight, id, taker, take_.offer, targetUnits - totalFilledUnits),
                    take_.obligationShares
                ),
                taker,
                address(0),
                "",
                receiverIfTakerIsSeller,
                take_.offer,
                take_.sig,
                take_.root,
                take_.proof
            ) returns (
                uint256, uint256, uint256 obligationUnits, uint256
            ) {
                totalFilledUnits += obligationUnits;
            } catch {}
        }

        require(totalFilledUnits == targetUnits, "insufficient liquidity");
    }

    /// @dev Same as bundleTakeShares but targets buyer assets.
    /// @dev Not usable if buyerPrice > WAD, because not all buyerAssets are reachable then.
    function bundleTakeBuyerAssets(
        Midnight midnight,
        uint256 targetBuyerAssets,
        address taker,
        address receiverIfTakerIsSeller,
        Take[] calldata takes
    ) external {
        require(taker == msg.sender || midnight.isAuthorized(taker, msg.sender), "UNAUTHORIZED");
        require(takes.length != 0, "empty takes");
        bytes20 id = midnight.touchObligation(takes[0].offer.obligation); // to have the correct trading fees.

        uint256 totalBuyerAssets;
        for (uint256 i; i < takes.length && totalBuyerAssets < targetBuyerAssets; i++) {
            Take calldata take_ = takes[i];
            try midnight.take(
                UtilsLib.min(
                    TakeAmountsLib.buyerAssetsToShares(
                        midnight, id, taker, take_.offer, targetBuyerAssets - totalBuyerAssets
                    ),
                    take_.obligationShares
                ),
                taker,
                address(0),
                "",
                receiverIfTakerIsSeller,
                take_.offer,
                take_.sig,
                take_.root,
                take_.proof
            ) returns (
                uint256 buyerAssets, uint256, uint256, uint256
            ) {
                totalBuyerAssets += buyerAssets;
            } catch {}
        }

        require(totalBuyerAssets == targetBuyerAssets, "insufficient liquidity");
    }

    /// @dev Same as bundleTakeShares but targets seller assets.
    function bundleTakeSellerAssets(
        Midnight midnight,
        uint256 targetSellerAssets,
        address taker,
        address receiverIfTakerIsSeller,
        Take[] calldata takes
    ) external {
        require(taker == msg.sender || midnight.isAuthorized(taker, msg.sender), "UNAUTHORIZED");
        require(takes.length != 0, "empty takes");
        bytes20 id = midnight.touchObligation(takes[0].offer.obligation); // to have the correct trading fees.

        uint256 totalSellerAssets;
        for (uint256 i; i < takes.length && totalSellerAssets < targetSellerAssets; i++) {
            Take calldata take_ = takes[i];
            try midnight.take(
                UtilsLib.min(
                    TakeAmountsLib.sellerAssetsToShares(
                        midnight, id, taker, take_.offer, targetSellerAssets - totalSellerAssets
                    ),
                    take_.obligationShares
                ),
                taker,
                address(0),
                "",
                receiverIfTakerIsSeller,
                take_.offer,
                take_.sig,
                take_.root,
                take_.proof
            ) returns (
                uint256, uint256 sellerAssets, uint256, uint256
            ) {
                totalSellerAssets += sellerAssets;
            } catch {}
        }

        require(totalSellerAssets == targetSellerAssets, "insufficient liquidity");
    }
}
