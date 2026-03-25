// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function creditOf(bytes32 id, address user) external returns (uint256) envfree;
    function debtOf(bytes32 id, address user) external returns (uint256) envfree;
    function userLossIndex(bytes32 id, address user) external returns (uint128) envfree;
    function collateralOf(bytes32 id, address user, uint256 index) external returns (uint128) envfree;
    function _.price() external => NONDET;

    // Summarize internals irrelevant to credit and debt tracking.
    function IdLib.storeInCode(Midnight.Obligation memory) internal returns (address) => NONDET;
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;
    function UtilsLib.msb(uint128) internal returns (uint256) => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDiv(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDiv(x, y, d);

    // Assume no reentrancy: callbacks and token transfers do not re-enter Midnight.
    // This is justified because the properties we verify are about the effect of each function's own
    // body on credit and debt, not the effect of the full transaction including callbacks.
    function _.onBuy(bytes32, Midnight.Obligation, address, uint256, uint256, uint256, bytes) external => NONDET;
    function _.onSell(bytes32, Midnight.Obligation, address, uint256, uint256, uint256, bytes) external => NONDET;
    function _.onLiquidate(bytes32, Midnight.Obligation, uint256, uint256, uint256, address, bytes) external => NONDET;
    function _.onFlashLoan(address, uint256, bytes) external => NONDET;
    function _.transfer(address, uint256) external => NONDET;
    function signer(bytes32, Midnight.Signature memory) internal returns (address) => NONDET;
}

/// HELPERS ///

function summaryMulDiv(uint256 x, uint256 y, uint256 d) returns uint256 {
    if (x == 0 || y == 0) return 0;
    if (d > 0 && y == d) return x;
    uint256 res;
    return res;
}

/// REPAY ///

/// Repay decreases onBehalf's debt by exactly units and only changes position[id][onBehalf].debt
rule repayEffects(env e, Midnight.Obligation obligation, uint256 units, address onBehalf, bytes32 anyId, address anyUser) {
    bytes32 id = toId(e, obligation);

    uint256 debtBefore = debtOf(id, onBehalf);
    uint256 otherCreditBefore = creditOf(anyId, anyUser);
    uint256 otherDebtBefore = debtOf(anyId, anyUser);

    repay(e, obligation, units, onBehalf);

    assert debtOf(id, onBehalf) == debtBefore - units;
    assert creditOf(anyId, anyUser) == otherCreditBefore;
    assert anyUser != onBehalf || anyId != id => debtOf(anyId, anyUser) == otherDebtBefore;
}

/// LIQUIDATE ///

/// Liquidate decreases the borrower's debt by at least repaidUnits,
/// and only changes position[id][borrower].debt.
rule liquidateEffects(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data, bytes32 anyId, address anyUser) {
    bytes32 id = toId(e, obligation);

    uint256 debtBefore = debtOf(id, borrower);
    uint256 otherCreditBefore = creditOf(anyId, anyUser);
    uint256 otherDebtBefore = debtOf(anyId, anyUser);

    uint256 seizedResult;
    uint256 repaidResult;
    seizedResult, repaidResult = liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);

    assert debtOf(id, borrower) <= debtBefore - repaidResult;
    assert creditOf(anyId, anyUser) == otherCreditBefore;
    assert anyUser != borrower || anyId != id => debtOf(anyId, anyUser) == otherDebtBefore;
}

/// ALL OTHER FUNCTIONS ///

/// Effects of take, withdraw, and updatePosition are checked in BalanceEffectsWithUpdate.spec.
/// Functions other than take, withdraw, repay, liquidate, updatePosition, and withdrawCollateral do not change any user's credit or debt.
rule creditAndDebtUnchangedByOtherFunctions(method f, env e, calldataarg args, bytes32 id, address user)
filtered {
    f -> !f.isView
        && f.selector != sig:take(uint256, address, address, bytes, address, Midnight.Offer, Midnight.Signature, bytes32, bytes32[]).selector
        && f.selector != sig:withdraw(Midnight.Obligation, uint256, address, address).selector
        && f.selector != sig:repay(Midnight.Obligation, uint256, address).selector
        && f.selector != sig:liquidate(Midnight.Obligation, uint256, uint256, uint256, address, bytes).selector
        && f.selector != sig:updatePosition(Midnight.Obligation, address).selector
} {
    uint256 creditBefore = creditOf(id, user);
    uint256 debtBefore = debtOf(id, user);
    f(e, args);
    assert creditOf(id, user) == creditBefore;
    assert debtOf(id, user) == debtBefore;
}

/// SUPPLY COLLATERAL ///

/// supplyCollateral increases onBehalf's collateral by exactly assets,
/// and only changes position[id][onBehalf].collateral[collateralIndex].
rule supplyCollateralEffects(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 assets, address onBehalf, bytes32 anyId, address anyUser, uint256 anyIndex) {
    bytes32 id = toId(e, obligation);

    uint256 collateralBefore = collateralOf(id, onBehalf, collateralIndex);
    uint256 otherCollateralBefore = collateralOf(anyId, anyUser, anyIndex);

    supplyCollateral(e, obligation, collateralIndex, assets, onBehalf);

    assert collateralOf(id, onBehalf, collateralIndex) == collateralBefore + assets;
    assert anyUser != onBehalf || anyId != id || anyIndex != collateralIndex => collateralOf(anyId, anyUser, anyIndex) == otherCollateralBefore;
}

/// WITHDRAW COLLATERAL ///

/// withdrawCollateral decreases onBehalf's collateral by exactly assets,
/// and only changes position[id][onBehalf].collateral[collateralIndex].
rule withdrawCollateralCollateralEffects(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 assets, address onBehalf, address receiver, bytes32 anyId, address anyUser, uint256 anyIndex) {
    bytes32 id = toId(e, obligation);

    uint256 collateralBefore = collateralOf(id, onBehalf, collateralIndex);
    uint256 otherCollateralBefore = collateralOf(anyId, anyUser, anyIndex);

    withdrawCollateral(e, obligation, collateralIndex, assets, onBehalf, receiver);

    assert collateralOf(id, onBehalf, collateralIndex) == collateralBefore - assets;
    assert anyUser != onBehalf || anyId != id || anyIndex != collateralIndex => collateralOf(anyId, anyUser, anyIndex) == otherCollateralBefore;
}

/// LIQUIDATE (COLLATERAL) ///

/// liquidate decreases the borrower's collateral at collateralIndex by exactly seizedResult,
/// and only changes position[id][borrower].collateral[collateralIndex].
rule liquidateCollateralEffects(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data, bytes32 anyId, address anyUser, uint256 anyIndex) {
    bytes32 id = toId(e, obligation);

    uint256 collateralBefore = collateralOf(id, borrower, collateralIndex);
    uint256 otherCollateralBefore = collateralOf(anyId, anyUser, anyIndex);

    uint256 seizedResult;
    seizedResult, _ = liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);

    assert collateralOf(id, borrower, collateralIndex) == collateralBefore - seizedResult;
    assert anyUser != borrower || anyId != id || anyIndex != collateralIndex => collateralOf(anyId, anyUser, anyIndex) == otherCollateralBefore;
}

/// ALL OTHER FUNCTIONS (COLLATERAL) ///

/// Functions other than supplyCollateral, withdrawCollateral, and liquidate do not change any user's collateral.
rule collateralUnchangedByOtherFunctions(method f, env e, calldataarg args, bytes32 id, address user, uint256 colIdx)
filtered {
    f -> !f.isView
        && f.selector != sig:supplyCollateral(Midnight.Obligation, uint256, uint256, address).selector
        && f.selector != sig:withdrawCollateral(Midnight.Obligation, uint256, uint256, address, address).selector
        && f.selector != sig:liquidate(Midnight.Obligation, uint256, uint256, uint256, address, bytes).selector
} {
    uint256 collateralBefore = collateralOf(id, user, colIdx);
    f(e, args);
    assert collateralOf(id, user, colIdx) == collateralBefore;
}
