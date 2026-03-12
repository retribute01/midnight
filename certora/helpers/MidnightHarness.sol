// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Midnight} from "../../src/Midnight.sol";
import {Obligation} from "../../src/interfaces/IMidnight.sol";

contract MidnightHarness is Midnight {
    constructor(address owner) Midnight(owner) {}

    function isHealthyExternal(Obligation memory obligation, bytes32 id, address borrower)
        external
        view
        returns (bool)
    {
        return isHealthy(obligation, id, borrower);
    }
}
