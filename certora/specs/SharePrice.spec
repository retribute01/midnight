// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function totalUnits(bytes32 id) external returns (uint256) envfree;
    function totalShares(bytes32 id) external returns (uint256) envfree;

    function _.price() external => NONDET;

    function tradingFee(bytes32, uint256) internal returns (uint256) => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;

    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function TickLib.wExp(int256) internal returns (uint256) => NONDET;
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;
    function UtilsLib.msb(uint256) internal returns (uint256) => NONDET;
    function UtilsLib.countBits(uint128) internal returns (uint256) => NONDET;

    function IdLib.toId(Midnight.Obligation memory, uint256, address) internal returns (bytes32) => NONDET;

    function isHealthy(Midnight.Obligation memory, bytes32, address) internal returns (bool) => NONDET;

    function pendingContinuousFee(bytes32 id, address borrower, uint256 maturity) internal returns (uint256) => summaryPendingContinuousFee(id, borrower);

    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivDown(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivUp(x, y, d);
}

function summaryMulDivDown(uint256 x, uint256 y, uint256 d) returns uint256 {
    if (x == 0 || y == 0) return 0;
    if (d > 0 && y == d) return x;
    if (d > 0 && x == d) return y;
    uint256 res;
    // Exact floor: res = floor(x*y/d).
    require to_mathint(res) * to_mathint(d) <= to_mathint(x) * to_mathint(y);
    require (to_mathint(res) + 1) * to_mathint(d) > to_mathint(x) * to_mathint(y);
    return res;
}

function summaryMulDivUp(uint256 x, uint256 y, uint256 d) returns uint256 {
    if (x == 0 || y == 0) return 0;
    if (d > 0 && y == d) return x;
    if (d > 0 && x == d) return y;
    uint256 res;
    // Exact ceil: res = ceil(x*y/d).
    require to_mathint(res) * to_mathint(d) >= to_mathint(x) * to_mathint(y);
    require res == 0 || (to_mathint(res) - 1) * to_mathint(d) < to_mathint(x) * to_mathint(y);
    return res;
}

function summaryPendingContinuousFee(bytes32 id, address borrower) returns uint256 {
    uint128 pf = currentContract.borrowerState[id][borrower].pendingFee;
    if (pf == 0) return 0;
    uint128 lastAccrual = currentContract.borrowerState[id][borrower].lastContinuousFeeAccrual;
    if (lastAccrual == 0) return 0;
    uint256 res;
    require to_mathint(res) <= to_mathint(pf);
    return res;
}

definition liquidationAccruesNoFee(bytes32 id, address borrower) returns bool = currentContract.borrowerState[id][borrower].pendingFee == 0 || currentContract.borrowerState[id][borrower].lastContinuousFeeAccrual == 0;

// Check the ratio of units over shares is below or equal to 1.
strong invariant sharePriceBelowOrEqOne(bytes32 id)
    totalShares(id) >= totalUnits(id);

/// If liquidation cannot accrue fee in the current call, it does not change the total shares.
rule liquidateWithoutFeeAccrualDoesNotChangeShares(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data, bytes32 id) {
    require liquidationAccruesNoFee(id, borrower), "exclude fee accrual";
    mathint sharesBefore = totalShares(id);
    liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);
    assert totalShares(id) == sharesBefore;
}

/// If liquidation cannot accrue fee in the current call, it does not increase the total units.
rule liquidateWithoutFeeAccrualDoesNotIncreaseUnits(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data, bytes32 id) {
    require liquidationAccruesNoFee(id, borrower), "exclude fee accrual";
    mathint unitsBefore = totalUnits(id);
    liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);
    assert totalUnits(id) <= unitsBefore;
}

/// Virtual share price = (totalUnits+1)/(totalShares+1) monotonicity.
/// Liquidation is excluded: it can decrease the share price via bad debt socialization but covered above.
rule sharePriceDoesNotDecrease(bytes32 id, method f) filtered { f -> f.selector != sig:liquidate(Midnight.Obligation, uint256, uint256, uint256, address, bytes).selector && !f.isView } {
    mathint unitsBefore = totalUnits(id);
    mathint sharesBefore = totalShares(id);

    env e;
    calldataarg args;
    f(e, args);

    mathint unitsAfter = totalUnits(id);
    mathint sharesAfter = totalShares(id);

    assert (unitsAfter + 1) * (sharesBefore + 1) >= (unitsBefore + 1) * (sharesAfter + 1);
}
