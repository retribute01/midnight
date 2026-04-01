// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.31;

import {Obligation} from "../interfaces/IMidnight.sol";
import {ICallbacks} from "../interfaces/ICallbacks.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {CALLBACK_SUCCESS} from "../libraries/ConstantsLib.sol";
import {SafeTransferLib} from "../libraries/SafeTransferLib.sol";

contract TransferFromCallback is ICallbacks {
    function onBuy(
        bytes32,
        Obligation memory obligation,
        address buyer,
        uint256 buyerAssets,
        uint256,
        uint256,
        bytes memory
    ) external returns (bytes32) {
        SafeTransferLib.safeTransferFrom(obligation.loanToken, buyer, address(this), buyerAssets);
        IERC20(obligation.loanToken).approve(msg.sender, buyerAssets);
        return CALLBACK_SUCCESS;
    }

    function onSell(bytes32, Obligation memory, address, uint256, uint256, uint256, bytes memory) external {}

    function onLiquidate(bytes32, Obligation memory, uint256, uint256, uint256, address, bytes memory) external {}
}
