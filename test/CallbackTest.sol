// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {BaseTest} from "./BaseTest.sol";
import {ICallbacks} from "../src/interfaces/ICallbacks.sol";
import {MorphoV2} from "../src/MorphoV2.sol";
import {Obligation, Offer, Collateral, Seizure} from "../src/interfaces/IMorphoV2.sol";
import {ERC20} from "./helpers/ERC20.sol";

