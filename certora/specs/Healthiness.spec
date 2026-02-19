// SPDX-License-Identifier: GPL-2.0-or-later

using Havoc as callback;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function withdrawable(bytes32 id) external returns (uint256) envfree;
    function totalUnits(bytes32 id) external returns (uint256) envfree;
    function totalShares(bytes32 id) external returns (uint256) envfree;
    function consumed(address user, bytes32 group) external returns (uint256) envfree;
    function sharesOf(bytes32 id, address owner) external returns (uint256) envfree;
    function debtOf(bytes32 id, address user) external returns (uint256) envfree;
    function isHealthy(MorphoV2.Obligation, bytes32, address) external returns (bool) envfree;

    function _.price() external => summaryPrice(calledContract) expect(uint256);
    function TickLib.tickToPrice(uint256 tick) internal returns (uint256) => NONDET;
    function IdLib.toId(MorphoV2.Obligation memory obligation, uint256 chainId, address morpho) internal returns (bytes32) => summaryToId(obligation, chainId, morpho);
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivDown(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivUp(x, y, d);

    function _.transferFrom(address from, address to, uint256 amount) external with(env e) => genericCallbackBool() expect (bool);
    function _.transfer(address to, uint256 amount) external with(env e) => genericCallbackBool() expect (bool);
    function _.onBuy(MorphoV2.Obligation obligation, address buyer, uint256 buyerAssets, uint256 sellerAssets, uint256 obligationUnits, uint256 obligationShares, bytes data) external => genericCallback() expect void;
    function _.onSell(MorphoV2.Obligation obligation, address seller, uint256 buyerAssets, uint256 sellerAssets, uint256 obligationUnits, uint256 obligationShares, bytes data) external => genericCallback() expect void;
    function _.onLiquidate(MorphoV2.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data) external => genericCallback() expect void;
    function _.onFlashLoan(address token, uint256 amount, bytes data) external => genericCallback() expect void;
}

/// SUMMARY ///

definition MAX_LIF() returns uint256 = 115 * 10^16;
definition WAD() returns uint256 = 10^18;

persistent ghost summaryPrice(address) returns uint256;
persistent ghost summaryMulDivDownM(mathint,mathint,mathint) returns mathint {
    axiom forall mathint b. forall mathint d. d > 0 =>
        summaryMulDivDownM(0, b, d) == 0;
    axiom forall mathint a1. forall mathint a2. forall mathint b. forall mathint d. d > 0 && a1 <= a2 =>
        summaryMulDivDownM(a1, b, d) <= summaryMulDivDownM(a2, b, d);
//    axiom forall mathint a1. forall mathint a2. forall mathint b. forall mathint d. d > 0 && a1 <= a2 =>
//        summaryMulDivDownM(a2 - a1, b, d) <= summaryMulDivDownM(a2, b, d) - summaryMulDivDownM(a1, b, d);
}
persistent ghost summaryMulDivUpM(mathint,mathint,mathint) returns mathint {
//    axiom forall mathint a. forall mathint b. forall mathint d. forall mathint x. b > 0 && d > 0 =>
//        a <= summaryMulDivDownM(summaryMulDivUpM(a, b, d), d, b);
    axiom forall mathint a. forall mathint b. forall mathint d. forall mathint x. b > 0 && d > 0 =>
        a >= summaryMulDivUpM(summaryMulDivDownM(a, b, d), d, b);

    axiom forall mathint a1. forall mathint a2. forall mathint b. forall mathint d. d > 0 && a1 <= a2 =>
        summaryMulDivDownM(a2 - a1, b, d) >= summaryMulDivDownM(a2, b, d) - summaryMulDivUpM(a1, b, d);
}

function summaryMulDivDown(uint256 a, uint256 b, uint256 d) returns uint256 {
    bool overflow;
    if (overflow || d == 0) {
        revert();
    }
    return require_uint256(summaryMulDivDownM(a, b, d));
}
function summaryMulDivUp(uint256 a, uint256 b, uint256 d) returns uint256 {
    bool overflow;
    if (overflow || d == 0) {
        revert();
    }
    return require_uint256(summaryMulDivUpM(a, b, d));
}


//persistent ghost MorphoV2.Obligation globalObligation;
persistent ghost address globalObligationLoanToken;
persistent ghost uint256 globalObligationCollateralLength;
persistent ghost mapping(uint256 => address) globalObligationCollateralOracle;
persistent ghost mapping(uint256 => address) globalObligationCollateralToken;
persistent ghost mapping(uint256 => uint256) globalObligationCollateralLLTV;
persistent ghost bytes32 globalId;
persistent ghost address globalBorrower;

function summaryToId(MorphoV2.Obligation obligation, uint256 chainId, address morpho) returns (bytes32) {
    bytes32 id;
    if (obligation.loanToken == globalObligationLoanToken
        && obligation.collaterals.length == globalObligationCollateralLength
        && (obligation.collaterals.length <= 0
         || (obligation.collaterals[0].oracle == globalObligationCollateralOracle[0]
        && obligation.collaterals[0].token == globalObligationCollateralToken[0]
        && obligation.collaterals[0].lltv == globalObligationCollateralLLTV[0]))
        && (obligation.collaterals.length <= 1
         || (obligation.collaterals[1].oracle == globalObligationCollateralOracle[1]
        && obligation.collaterals[1].token == globalObligationCollateralToken[1]
        && obligation.collaterals[1].lltv == globalObligationCollateralLLTV[1]))
        && (obligation.collaterals.length <= 2
         || (obligation.collaterals[2].oracle == globalObligationCollateralOracle[2]
        && obligation.collaterals[2].token == globalObligationCollateralToken[2]
        && obligation.collaterals[2].lltv == globalObligationCollateralLLTV[2]))
        && (obligation.collaterals.length <= 3
         || (obligation.collaterals[3].oracle == globalObligationCollateralOracle[3]
        && obligation.collaterals[3].token == globalObligationCollateralToken[3]
        && obligation.collaterals[3].lltv == globalObligationCollateralLLTV[3]))
        && morpho == currentContract) {
        require id == globalId;
    } else {
        require id != globalId;
    }
    return id;
}

function genericCallback() {
    address dummy;
    env e;
    MorphoV2.Obligation obligation;

    require obligation.loanToken == globalObligationLoanToken;
    require obligation.collaterals.length == globalObligationCollateralLength;
    require forall uint256 i. 0 <= i && i < globalObligationCollateralLength =>
        obligation.collaterals[i].oracle == globalObligationCollateralOracle[i]
        && obligation.collaterals[i].token == globalObligationCollateralToken[i]
        && obligation.collaterals[i].lltv == globalObligationCollateralLLTV[i];

    assert isHealthy(obligation, globalId, globalBorrower);

    callback.callHavoc(e, dummy);

    require isHealthy(obligation, globalId, globalBorrower);
}

function genericCallbackBool() returns (bool) {
    bool result;

    genericCallback();
    return result;
}

rule stayHealthy(env e, method f, calldataarg args) {
    MorphoV2.Obligation obligation;

    require forall uint256 a. forall uint256 lif. forall uint256 i. 
        0 <= i && i < globalObligationCollateralLength && lif <= MAX_LIF() =>
        summaryMulDivUpM(a, WAD(), lif)  >= summaryMulDivUpM(a, obligation.collaterals[i].lltv, WAD()),
        "collateral lltv must be less then 1/MAX_LIF";

//    require forall uint256 i. 0 <= i && i < globalObligationCollateralLength =>
//        obligation.collaterals[i].lltv * 115 * 10^16  < 10^36, "collateral lltv must be less then 1/MAX_LIF";

    require obligation.loanToken == globalObligationLoanToken;
    require obligation.collaterals.length == globalObligationCollateralLength;
    require forall uint256 i. 0 <= i && i < globalObligationCollateralLength =>
        obligation.collaterals[i].oracle == globalObligationCollateralOracle[i]
        && obligation.collaterals[i].token == globalObligationCollateralToken[i]
        && obligation.collaterals[i].lltv == globalObligationCollateralLLTV[i];

    require isHealthy(obligation, globalId, globalBorrower);

    f(e, args);

    assert isHealthy(obligation, globalId, globalBorrower);
}
