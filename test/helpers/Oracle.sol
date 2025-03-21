// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

contract Oracle {
    uint256 public price = 1e36;

    function setPrice(uint256 newPrice) external {
        price = newPrice;
    }
}
