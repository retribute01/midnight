// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function tradingFee(bytes32 id, uint256 timeToMaturity) external returns (uint256) envfree;
    function maxTradingFee(uint256 index) external returns (uint256) envfree;

    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;

    function isHealthy(Midnight.Obligation memory, bytes32, address) internal returns (bool) => NONDET;
}

definition FEE_STEP() returns mathint = 1000000000000; // 1e12

/// Per-index max fee units — must match maxTradingFee(index) / FEE_STEP.
/// CVL definitions are needed here because contract calls are disallowed inside quantified formulas.

definition maxFeeUnits(uint256 index) returns mathint = index == 0 ? 14 : index == 1 ? 14 : index == 2 ? 98 : index == 3 ? 417 : index == 4 ? 1250 : index == 5 ? 2500 : 5000;

/// Persistent: these ghosts track Midnight's own storage, which is not havoced by HAVOC_ECF
/// from external callbacks (onFlashLoan, onBuy, onSell, onLiquidate).
persistent ghost mapping(bytes32 => mapping(uint256 => mathint)) ghostObligationFeeUnits {
    init_state axiom forall bytes32 id. forall uint256 i. ghostObligationFeeUnits[id][i] == 0;
}

persistent ghost mapping(address => mapping(uint256 => mathint)) ghostDefaultFeeUnits {
    init_state axiom forall address t. forall uint256 i. ghostDefaultFeeUnits[t][i] == 0;
}

hook Sstore obligationState[KEY bytes32 id].fees[INDEX uint256 idx] uint16 newVal {
    ghostObligationFeeUnits[id][idx] = to_mathint(newVal);
}

hook Sload uint16 val obligationState[KEY bytes32 id].fees[INDEX uint256 idx] {
    require ghostObligationFeeUnits[id][idx] == to_mathint(val);
}

hook Sstore defaultFees[KEY address token][INDEX uint256 idx] uint16 newVal {
    ghostDefaultFeeUnits[token][idx] = to_mathint(newVal);
}

hook Sload uint16 val defaultFees[KEY address token][INDEX uint256 idx] {
    require ghostDefaultFeeUnits[token][idx] == to_mathint(val);
}

/// Default fees for any loan token at each index are bounded by its specific maxTradingFee cap.
invariant defaultFeePerIndexBound(address loanToken, uint256 index)
    index <= 6 => ghostDefaultFeeUnits[loanToken][index] <= maxFeeUnits(index);

/// Every obligation's fee breakpoints are bounded by the per-index maximum.
invariant obligationFeePerIndexBound(bytes32 id, uint256 index)
    index <= 6 => ghostObligationFeeUnits[id][index] <= maxFeeUnits(index)
    {
        preserved with (env e) {
            require forall address t. forall uint256 i. i <= 6 => ghostDefaultFeeUnits[t][i] <= maxFeeUnits(i);
        }
    }

/// If all fee breakpoints are zero in storage, the trading fee is zero everywhere.
rule zeroFeesImplyZeroTradingFee(bytes32 id, uint256 timeToMaturity) {
    require forall uint256 i. i <= 6 => ghostObligationFeeUnits[id][i] == 0;

    assert tradingFee(id, timeToMaturity) == 0;
}

/// tradingFee(id, t) <= maxTradingFee(6) for any time to maturity.
rule tradingFeeAlwaysWithinMaxFee(bytes32 id, uint256 timeToMaturity) {
    requireInvariant obligationFeePerIndexBound(id, 0);
    requireInvariant obligationFeePerIndexBound(id, 1);
    requireInvariant obligationFeePerIndexBound(id, 2);
    requireInvariant obligationFeePerIndexBound(id, 3);
    requireInvariant obligationFeePerIndexBound(id, 4);
    requireInvariant obligationFeePerIndexBound(id, 5);
    requireInvariant obligationFeePerIndexBound(id, 6);

    assert tradingFee(id, timeToMaturity) <= maxTradingFee(6);
}

/// The interpolated fee never exceeds any upper bound that all breakpoint values satisfy.
rule tradingFeeBoundedByBreakpoints(bytes32 id, uint256 timeToMaturity, uint256 upperBound) {
    require tradingFee(id, 0) <= upperBound;
    require tradingFee(id, 86400) <= upperBound;
    require tradingFee(id, 604800) <= upperBound;
    require tradingFee(id, 2592000) <= upperBound;
    require tradingFee(id, 7776000) <= upperBound;
    require tradingFee(id, 15552000) <= upperBound;
    require tradingFee(id, 31104000) <= upperBound;

    assert tradingFee(id, timeToMaturity) <= upperBound;
}

/// The interpolated fee never drops below any lower bound that all breakpoint values satisfy.
rule tradingFeeLowerBoundedByBreakpoints(bytes32 id, uint256 timeToMaturity, uint256 lowerBound) {
    require tradingFee(id, 0) >= lowerBound;
    require tradingFee(id, 86400) >= lowerBound;
    require tradingFee(id, 604800) >= lowerBound;
    require tradingFee(id, 2592000) >= lowerBound;
    require tradingFee(id, 7776000) >= lowerBound;
    require tradingFee(id, 15552000) >= lowerBound;
    require tradingFee(id, 31104000) >= lowerBound;

    assert tradingFee(id, timeToMaturity) >= lowerBound;
}
