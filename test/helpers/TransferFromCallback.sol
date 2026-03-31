// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Obligation} from "../../src/interfaces/IMidnight.sol";
import {ICallbacks} from "../../src/interfaces/ICallbacks.sol";
import {ERC20} from "./ERC20.sol";

contract TransferFromCallback is ICallbacks {
    function onBuy(
        bytes32,
        Obligation memory obligation,
        address buyer,
        uint256 buyerAssets,
        uint256,
        uint256,
        bytes memory
    ) external {
        require(ERC20(obligation.loanToken).transferFrom(buyer, msg.sender, buyerAssets));
    }

    function onSell(bytes32, Obligation memory, address, uint256, uint256, uint256, bytes memory) external {}

    function onLiquidate(bytes32, Obligation memory, uint256, uint256, uint256, address, bytes memory) external {}
}
