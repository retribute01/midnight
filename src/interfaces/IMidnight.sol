// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

struct Obligation {
    address loanToken;
    CollateralParams[] collateralParams;
    uint256 maturity;
    uint256 rcfThreshold;
    address enterGate;
    address liquidatorGate;
}

struct CollateralParams {
    address token;
    uint256 lltv;
    uint256 maxLif;
    address oracle;
}

struct Offer {
    Obligation obligation;
    bool buy;
    address maker;
    uint256 start;
    uint256 expiry;
    uint256 tick;
    bytes32 group;
    bytes32 session;
    address callback;
    bytes callbackData;
    address receiverIfMakerIsSeller;
    address ratifier;
    bool reduceOnly;
    uint256 maxUnits;
    uint256 maxSellerAssets;
    uint256 maxBuyerAssets;
}

struct ObligationState {
    uint128 totalUnits;
    uint128 lossIndex;
    uint128 withdrawable;
    uint128 continuousFeeCredit;
    uint16 fee0;
    uint16 fee1;
    uint16 fee2;
    uint16 fee3;
    uint16 fee4;
    uint16 fee5;
    uint16 fee6;
    uint32 continuousFee;
    bool created;
}

struct Position {
    uint128 credit;
    uint128 pendingFee;
    uint128 lossIndex;
    uint128 lastAccrual;
    uint128 debt;
    uint128 activatedCollaterals;
    uint128[128] collateral;
}

interface IMidnight {
    function isAuthorized(address authorizer, address authorized) external view returns (bool);
    function setIsAuthorized(address onBehalf, address authorized, bool newIsAuthorized) external;
}
