// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function balanceOf(bytes32 id, address user) external returns (int256) envfree;
    function balanceOfAfterSlashing(bytes32 id, address user) external returns (int256) envfree;
    function toId(Midnight.Obligation) external returns (bytes32);

    function _.price() external => NONDET;

    // Summarize internals irrelevant to balance tracking.
    function IdLib.storeInCode(Midnight.Obligation memory) internal returns (address) => NONDET;
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;
    function UtilsLib.msb(uint256) internal returns (uint256) => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function TickLib.wExp(int256) internal returns (uint256) => NONDET;
    function isHealthy(Midnight.Obligation memory, bytes32, address) internal returns (bool) => NONDET;
    function tradingFee(bytes32, uint256) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDiv(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDiv(x, y, d);

    // Assume no reentrancy: callbacks and token transfers do not re-enter Midnight.
    function _.onBuy(Midnight.Obligation, address, uint256, uint256, uint256, bytes) external => NONDET;
    function _.onSell(Midnight.Obligation, address, uint256, uint256, uint256, bytes) external => NONDET;
    function _.onLiquidate(Midnight.Obligation, uint256, uint256, uint256, address, bytes) external => NONDET;
    function _.onFlashLoan(address, uint256, bytes) external => NONDET;
    function _.transfer(address, uint256) external => NONDET;
    function _.transferFrom(address, address, uint256) external => NONDET;

    function signer(bytes32, Midnight.Signature memory) internal returns (address) => NONDET;
}

/// HELPERS ///

// Deterministic summary: same inputs always produce the same output.
// This is needed so that balanceOfAfterSlashing (view) agrees with the actual slash.
ghost ghostMulDiv(uint256, uint256, uint256) returns uint256;

function summaryMulDiv(uint256 x, uint256 y, uint256 d) returns uint256 {
    if (x == 0 || y == 0) return 0;
    return ghostMulDiv(x, y, d);
}

/// REPAY ///

/// repay increases onBehalf's balance by exactly obligationUnits.
rule repayIncreasesBalanceExactly(env e, Midnight.Obligation obligation, uint256 obligationUnits, address onBehalf) {
    bytes32 id = toId(e, obligation);
    int256 balanceBefore = balanceOf(id, onBehalf);
    repay(e, obligation, obligationUnits, onBehalf);
    int256 balanceAfter = balanceOf(id, onBehalf);
    assert to_mathint(balanceAfter) == to_mathint(balanceBefore) + to_mathint(obligationUnits);
}

/// repay only changes position[id][onBehalf].balance.
rule repayOnlyChangesTargetBalance(env e, Midnight.Obligation obligation, uint256 obligationUnits, address onBehalf, bytes32 anyId, address anyUser) {
    bytes32 id = toId(e, obligation);
    require anyUser != onBehalf || anyId != id;
    int256 balanceBefore = balanceOf(anyId, anyUser);
    repay(e, obligation, obligationUnits, onBehalf);
    int256 balanceAfter = balanceOf(anyId, anyUser);
    assert balanceAfter == balanceBefore;
}

/// WITHDRAW ///

/// withdraw decreases onBehalf's post-slash balance by exactly obligationUnits.
rule withdrawDecreasesBalanceExactly(env e, Midnight.Obligation obligation, uint256 obligationUnits, address onBehalf, address receiver) {
    bytes32 id = toId(e, obligation);
    int256 balanceBeforeSlash = balanceOfAfterSlashing(id, onBehalf);
    withdraw(e, obligation, obligationUnits, onBehalf, receiver);
    int256 balanceAfter = balanceOf(id, onBehalf);
    assert to_mathint(balanceAfter) == to_mathint(balanceBeforeSlash) - to_mathint(obligationUnits);
}

/// After withdraw, onBehalf's balance is non-negative.
rule withdrawLeavesNonNegativeBalance(env e, Midnight.Obligation obligation, uint256 obligationUnits, address onBehalf, address receiver) {
    bytes32 id = toId(e, obligation);
    withdraw(e, obligation, obligationUnits, onBehalf, receiver);
    int256 balanceAfter = balanceOf(id, onBehalf);
    assert balanceAfter >= 0;
}

/// withdraw only changes position[id][onBehalf].balance.
rule withdrawOnlyChangesTargetBalance(env e, Midnight.Obligation obligation, uint256 obligationUnits, address onBehalf, address receiver, bytes32 anyId, address anyUser) {
    bytes32 id = toId(e, obligation);
    require anyUser != onBehalf || anyId != id;
    int256 balanceBefore = balanceOf(anyId, anyUser);
    withdraw(e, obligation, obligationUnits, onBehalf, receiver);
    int256 balanceAfter = balanceOf(anyId, anyUser);
    assert balanceAfter == balanceBefore;
}

/// TAKE ///

/// take changes maker's balance by +/- obligationUnits relative to its post-slash balance.
rule takeChangesMakerBalance(env e, uint256 obligationUnits, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof) {
    bytes32 id = toId(e, offer.obligation);
    int256 makerPostSlash = balanceOfAfterSlashing(id, offer.maker);

    take(e, obligationUnits, taker, takerCallback, takerCallbackData, receiver, offer, signature, root, proof);

    int256 makerAfter = balanceOf(id, offer.maker);
    mathint delta = offer.buy ? to_mathint(obligationUnits) : -to_mathint(obligationUnits);
    assert to_mathint(makerAfter) == to_mathint(makerPostSlash) + delta;
}

/// take changes taker's balance by +/- obligationUnits relative to its post-slash balance.
rule takeChangesTakerBalance(env e, uint256 obligationUnits, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof) {
    bytes32 id = toId(e, offer.obligation);
    int256 takerPostSlash = balanceOfAfterSlashing(id, taker);

    take(e, obligationUnits, taker, takerCallback, takerCallbackData, receiver, offer, signature, root, proof);

    int256 takerAfter = balanceOf(id, taker);
    mathint delta = offer.buy ? -to_mathint(obligationUnits) : to_mathint(obligationUnits);
    assert to_mathint(takerAfter) == to_mathint(takerPostSlash) + delta;
}

/// take only changes balances of maker and taker at the obligation id.
rule takeOnlyChangesMakerAndTakerBalances(env e, uint256 obligationUnits, address taker, address takerCallback, bytes takerCallbackData, address receiver, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof, bytes32 anyId, address anyUser) {
    bytes32 id = toId(e, offer.obligation);
    require anyId != id || (anyUser != offer.maker && anyUser != taker);
    int256 balanceBefore = balanceOf(anyId, anyUser);
    take(e, obligationUnits, taker, takerCallback, takerCallbackData, receiver, offer, signature, root, proof);
    int256 balanceAfter = balanceOf(anyId, anyUser);
    assert balanceAfter == balanceBefore;
}

/// LIQUIDATE ///

/// liquidate increases the borrower's balance by at least repaidUnits.
rule liquidateIncreasesBalanceByAtLeastRepaid(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data) {
    bytes32 id = toId(e, obligation);
    int256 balanceBefore = balanceOf(id, borrower);
    uint256 seizedResult;
    uint256 repaidResult;
    seizedResult, repaidResult = liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);
    int256 balanceAfter = balanceOf(id, borrower);
    assert to_mathint(balanceAfter) >= to_mathint(balanceBefore) + to_mathint(repaidResult);
}

/// After liquidate with non-zero repayment, the borrower's balance is non-positive.
rule liquidateLeavesNonPositiveBalance(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data) {
    bytes32 id = toId(e, obligation);
    uint256 seizedResult;
    uint256 repaidResult;
    seizedResult, repaidResult = liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);
    int256 balanceAfter = balanceOf(id, borrower);
    assert repaidResult > 0 => balanceAfter <= 0;
}

/// liquidate only changes position[id][borrower].balance.
rule liquidateOnlyChangesTargetBalance(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data, bytes32 anyId, address anyUser) {
    bytes32 id = toId(e, obligation);
    require anyUser != borrower || anyId != id;
    int256 balanceBefore = balanceOf(anyId, anyUser);
    liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);
    int256 balanceAfter = balanceOf(anyId, anyUser);
    assert balanceAfter == balanceBefore;
}

/// SLASH ///

/// slash does not change non-positive balances.
rule slashPreservesNonPositiveBalance(env e, bytes32 id, address user) {
    int256 balanceBefore = balanceOf(id, user);
    require balanceBefore <= 0;
    slash(e, id, user);
    int256 balanceAfter = balanceOf(id, user);
    assert balanceAfter == balanceBefore;
}

/// slash only changes position[id][user].balance.
rule slashOnlyChangesTargetBalance(env e, bytes32 id, address user, bytes32 anyId, address anyUser) {
    require anyUser != user || anyId != id;
    int256 balanceBefore = balanceOf(anyId, anyUser);
    slash(e, id, user);
    int256 balanceAfter = balanceOf(anyId, anyUser);
    assert balanceAfter == balanceBefore;
}

/// ALL OTHER FUNCTIONS ///

/// Functions other than take, withdraw, repay, liquidate, and slash do not change any user's balance.
rule balanceUnchangedByOtherFunctions(method f, env e, calldataarg args, bytes32 id, address user)
filtered {
    f -> !f.isView
        && f.selector != sig:take(uint256, address, address, bytes, address, Midnight.Offer, Midnight.Signature, bytes32, bytes32[]).selector
        && f.selector != sig:withdraw(Midnight.Obligation, uint256, address, address).selector
        && f.selector != sig:repay(Midnight.Obligation, uint256, address).selector
        && f.selector != sig:liquidate(Midnight.Obligation, uint256, uint256, uint256, address, bytes).selector
        && f.selector != sig:slash(bytes32, address).selector
} {
    int256 balanceBefore = balanceOf(id, user);
    f(e, args);
    int256 balanceAfter = balanceOf(id, user);
    assert balanceAfter == balanceBefore;
}
