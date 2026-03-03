// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.31;

import {Midnight} from "../Midnight.sol";
import {Offer, Signature} from "../interfaces/IMidnight.sol";
import {UtilsLib} from "../libraries/UtilsLib.sol";

contract TakeBundler {
    /// @dev Iterates through orders, filling up to `targetShares` obligation shares total.
    /// @dev Assumes all offers share the same obligation id so that obligation shares are comparable.
    /// @dev The taker must have authorized this bundler and the msg.sender (if different from the taker) on Midnight.
    /// @dev The bundler skips every reason why `take` can revert (including ones that are not asynchrony related).
    /// @dev If taking an offer reverts with shares = min(targetShares - filled, obligationShares[i]), the bundler will
    /// completely skip this offer (even if a smaller could have been takeable).
    function bundleTake(
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
        require(
            obligationShares.length == offers.length && offers.length == sigs.length && offers.length == roots.length
                && offers.length == proofs.length,
            "length mismatch"
        );

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

        require(filled >= targetShares, "insufficient liquidity");
    }
}
