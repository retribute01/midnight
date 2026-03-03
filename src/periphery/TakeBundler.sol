// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.31;

import {Midnight} from "../Midnight.sol";
import {Offer, Signature} from "../interfaces/IMidnight.sol";
import {UtilsLib} from "../libraries/UtilsLib.sol";
import {TakeAmountsLib} from "./TakeAmountsLib.sol";

contract TakeBundler {
    using UtilsLib for uint256;

    /// @dev Iterates through orders, filling up to `targetShares` obligation shares total.
    /// @dev Assumes all offers share the same obligation id so that obligation shares are comparable.
    /// @dev The taker must have authorized this bundler and the msg.sender (if different from the taker) on Midnight.
    /// @dev The bundler skips every reason why `take` can revert (including ones that are not asynchrony related).
    /// @dev If taking an offer reverts, the bundler will completely skip this offer.
    /// @dev Assumes obligationShares, offers, sigs, roots, and proofs all have the same length.
    function bundleTakeShares(
        Midnight midnight,
        uint256 targetShares,
        address taker,
        address takerCallback,
        bytes calldata takerCallbackData,
        address receiverIfTakerIsSeller,
        uint256[] calldata obligationShares,
        Offer[] calldata offers,
        Signature[] calldata sigs,
        bytes32[] calldata roots,
        bytes32[][] calldata proofs
    ) external {
        require(taker == msg.sender || midnight.isAuthorized(taker, msg.sender), "UNAUTHORIZED");

        uint256 filled;
        for (uint256 i; i < offers.length && filled < targetShares; i++) {
            try midnight.take(
                UtilsLib.min(targetShares - filled, obligationShares[i]),
                taker,
                takerCallback,
                takerCallbackData,
                receiverIfTakerIsSeller,
                offers[i],
                sigs[i],
                roots[i],
                proofs[i]
            ) returns (
                uint256, uint256, uint256, uint256 filledShares
            ) {
                filled += filledShares;
            } catch {}
        }

        require(filled == targetShares, "insufficient liquidity");
    }

    /// @dev Assumes obligationShares, offers, sigs, roots, and proofs all have the same length.
    /// @dev Same as bundleTakeShares but targets obligation units.
    function bundleTakeUnits(
        Midnight midnight,
        uint256 targetUnits,
        address taker,
        address takerCallback,
        bytes calldata takerCallbackData,
        address receiverIfTakerIsSeller,
        uint256[] calldata obligationShares,
        Offer[] calldata offers,
        Signature[] calldata sigs,
        bytes32[] calldata roots,
        bytes32[][] calldata proofs
    ) external {
        require(taker == msg.sender || midnight.isAuthorized(taker, msg.sender), "UNAUTHORIZED");
        bytes20 id = midnight.touchObligation(offers[0].obligation); // to have the correct trading fees.

        uint256 filled;
        for (uint256 i; i < offers.length && filled < targetUnits; i++) {
            try midnight.take(
                UtilsLib.min(
                    TakeAmountsLib.unitsToShares(midnight, id, taker, offers[i], targetUnits - filled),
                    obligationShares[i]
                ),
                taker,
                takerCallback,
                takerCallbackData,
                receiverIfTakerIsSeller,
                offers[i],
                sigs[i],
                roots[i],
                proofs[i]
            ) returns (
                uint256, uint256, uint256 obligationUnits, uint256
            ) {
                filled += obligationUnits;
            } catch {}
        }

        require(filled == targetUnits, "insufficient liquidity");
    }

    /// @dev Assumes obligationShares, offers, sigs, roots, and proofs all have the same length.
    /// @dev Same as bundleTakeShares but targets buyer assets.
    function bundleTakeBuyerAssets(
        Midnight midnight,
        uint256 targetBuyerAssets,
        address taker,
        address takerCallback,
        bytes calldata takerCallbackData,
        address receiverIfTakerIsSeller,
        uint256[] calldata obligationShares,
        Offer[] calldata offers,
        Signature[] calldata sigs,
        bytes32[] calldata roots,
        bytes32[][] calldata proofs
    ) external {
        require(taker == msg.sender || midnight.isAuthorized(taker, msg.sender), "UNAUTHORIZED");
        bytes20 id = midnight.touchObligation(offers[0].obligation); // to have the correct trading fees.

        uint256 filled;
        for (uint256 i; i < offers.length && filled < targetBuyerAssets; i++) {
            try midnight.take(
                UtilsLib.min(
                    TakeAmountsLib.buyerAssetsToShares(midnight, id, taker, offers[i], targetBuyerAssets - filled),
                    obligationShares[i]
                ),
                taker,
                takerCallback,
                takerCallbackData,
                receiverIfTakerIsSeller,
                offers[i],
                sigs[i],
                roots[i],
                proofs[i]
            ) returns (
                uint256 buyerAssets, uint256, uint256, uint256
            ) {
                filled += buyerAssets;
            } catch {}
        }

        require(filled == targetBuyerAssets, "insufficient liquidity");
    }

    /// @dev Assumes obligationShares, offers, sigs, roots, and proofs all have the same length.
    /// @dev Same as bundleTakeShares but targets seller assets.
    function bundleTakeSellerAssets(
        Midnight midnight,
        uint256 targetSellerAssets,
        address taker,
        address takerCallback,
        bytes calldata takerCallbackData,
        address receiverIfTakerIsSeller,
        uint256[] calldata obligationShares,
        Offer[] calldata offers,
        Signature[] calldata sigs,
        bytes32[] calldata roots,
        bytes32[][] calldata proofs
    ) external {
        require(taker == msg.sender || midnight.isAuthorized(taker, msg.sender), "UNAUTHORIZED");
        bytes20 id = midnight.touchObligation(offers[0].obligation); // to have the correct trading fees.

        uint256 filled;
        for (uint256 i; i < offers.length && filled < targetSellerAssets; i++) {
            try midnight.take(
                UtilsLib.min(
                    TakeAmountsLib.sellerAssetsToShares(midnight, id, taker, offers[i], targetSellerAssets - filled),
                    obligationShares[i]
                ),
                taker,
                takerCallback,
                takerCallbackData,
                receiverIfTakerIsSeller,
                offers[i],
                sigs[i],
                roots[i],
                proofs[i]
            ) returns (
                uint256, uint256 sellerAssets, uint256, uint256
            ) {
                filled += sellerAssets;
            } catch {}
        }

        require(filled == targetSellerAssets, "insufficient liquidity");
    }
}
