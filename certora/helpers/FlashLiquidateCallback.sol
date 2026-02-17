// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Seizure} from "../../src/interfaces/IMorphoV2.sol";

interface IHavoc {
    function havoc() external;
}

contract FlashLiquidateCallback {
    function startFlashloan(address token, uint256 amount) internal {
        // Dummy function to insert the flashloan logic in the spec.
    }

    function endFlashloan(address token, uint256 amount) internal {
        // Dummy function to insert the flashloan logic in the spec.
    }

    function startFlashloanForLiquidity(uint256 amount) internal {
        // Dummy function to insert the flashloan logic in the spec.
    }

    function endFlashloanForLiquidity(uint256 amount) internal {
        // Dummy function to insert the flashloan logic in the spec.
    }

    function onLiquidate(Seizure[] memory seizures, address, address, bytes memory data) external {
        uint256 totalAmount;
        for (uint256 i = 0; i < seizures.length; i++) {
            totalAmount += seizures[i].repaid;
        }
        startFlashloanForLiquidity(totalAmount);
        address account = abi.decode(data, (address));
        IHavoc(account).havoc();
        endFlashloanForLiquidity(totalAmount);
    }

    function onFlashLoan(address token, uint256 amount, bytes calldata data) external {
        startFlashloan(token, amount);
        address account = abi.decode(data, (address));
        IHavoc(account).havoc();
        endFlashloan(token, amount);
    }
}
