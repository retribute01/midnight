// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

library Math {
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function exactlyOneZero(uint256 a, uint256 b) internal pure returns (bool) {
        return (a == 0 && b != 0) || (a != 0 && b == 0);
    }
}
