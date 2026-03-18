// SPDX-License-Identifier: GPL-2.0-or-later

import "Midnight.spec";

methods {
    function feeRecipient() external returns (address) envfree;
    function toId(Midnight.Obligation obligation) external returns (bytes32) envfree;
    function creditOf(bytes32 id, address user) external returns (uint256) envfree;
    function debtOf(bytes32 id, address user) external returns (uint256) envfree;
    function isAuthorized(address authorizer, address authorized) external returns (bool) envfree;

    // Summarize internal functions that use opcodes causing HAVOC (CREATE2, low-level calls).
    function IdLib.storeInCode(Midnight.Obligation memory) internal returns (address) => NONDET;

    // Assume no reentrancy: callbacks do not re-enter Midnight.
    function _.onBuy(Midnight.Obligation, address, uint256, uint256, uint256, bytes) external => NONDET;
    function _.onSell(Midnight.Obligation, address, uint256, uint256, uint256, bytes) external => NONDET;
    function _.onFlashLoan(address, uint256, bytes) external => NONDET;

    function signer(bytes32, Midnight.Signature memory) internal returns (address) => CVL_signer();
}

/// HELPERS ///

function accruedContinuousFeeBefore(bytes32 id, address user, uint256 blockTimestamp, uint256 maturity) returns mathint {
    mathint lastAccrual = currentContract.position[id][user].lastContinuousFeeAccrual;
    mathint _pendingFee = currentContract.position[id][user].pendingFee;

    if (lastAccrual == 0 || maturity <= require_uint256(lastAccrual)) return 0;

    uint256 accrualEnd = blockTimestamp < maturity ? blockTimestamp : maturity;

    // Use the same mulDiv summary as the code to ensure consistency.
    return summaryMulDiv(assert_uint256(_pendingFee), assert_uint256(accrualEnd - lastAccrual), assert_uint256(maturity - lastAccrual));
}

definition noAccrual(env e, bytes32 id, address borrower) returns bool = currentContract.position[id][borrower].pendingFee == 0 || e.block.timestamp == currentContract.position[id][borrower].lastContinuousFeeAccrual;

use invariant noRemainingContinuousFeeWithoutDebt;

ghost mapping(address => bool) signed {
    init_state axiom forall address a. signed[a] == false;
}

function CVL_signer() returns address {
    address result;
    signed[result] = true;
    return result;
}

/// CREDIT AND DEBT CHANGE RULES ///

/// An unauthorized caller cannot change a user's credit and debt except via liquidate and slash.
/// Assumes no reentrancy: callbacks (onBuy, onSell) and token transfers are not modeled as re-entering Midnight, so re-entrant credit and debt changes are not covered.
rule onlyAuthorizedCanChangeCreditAndDebtExceptLiquidateAndSlash(env e, method f, calldataarg args, bytes32 id, address user) filtered { f -> f.selector != sig:liquidate(Midnight.Obligation, uint256, uint256, uint256, address, bytes).selector && f.selector != sig:slash(bytes32, address).selector } {
    bool userIsAuthorized = user == e.msg.sender || isAuthorized(user, e.msg.sender);

    uint256 creditBefore = creditOf(id, user);
    uint256 debtBefore = debtOf(id, user);
    f(e, args);
    uint256 creditAfter = creditOf(id, user);
    uint256 debtAfter = debtOf(id, user);

    assert (creditAfter == creditBefore && debtAfter == debtBefore) || userIsAuthorized || signed[user];
}

/// A user whose debt is zero can only become a borrower via take.
rule zeroDebtOnlyIncreasesViaTake(env e, method f, calldataarg args, bytes32 id, address user) {
    uint256 debtBefore = debtOf(id, user);

    requireInvariant noRemainingContinuousFeeWithoutDebt(id, user);

    f(e, args);

    assert debtBefore > 0 || debtOf(id, user) == 0 || f.selector == sig:take(uint256, address, address, bytes, address, Midnight.Offer, Midnight.Signature, bytes32, bytes32[]).selector;
}

/// In liquidate, only the borrower's debt can change, and any increase is bounded by accrued fee.
rule liquidateCanChangeDebt(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data, address user) {
    bytes32 id = toId(obligation);
    require noAccrual(e, id, borrower);

    mathint debtBefore = debtOf(id, user);

    liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);
    mathint debtAfter = debtOf(id, user);

    assert user == borrower => debtAfter <= debtBefore;
    assert user != borrower => debtAfter == debtBefore;
}

/// In take, the caller must be authorized by the taker, and only the buyer's or seller's debt can change.
/// Assumes no reentrancy: the onBuy/onSell callbacks could re-enter take (or another function) and change a different user's debt.
rule takeOnlyAuthorizedCanChangeDebt(env e, uint256 obligationUnits, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof, bytes32 id, address user) {
    address buyer = offer.buy ? offer.maker : taker;
    address seller = offer.buy ? taker : offer.maker;
    bool takerUnauthorized = e.msg.sender != taker && !isAuthorized(taker, e.msg.sender);

    uint256 debtBefore = debtOf(id, user);
    take@withrevert(e, obligationUnits, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, signature, root, proof);
    bool reverted = lastReverted;
    uint256 debtAfter = debtOf(id, user);

    assert takerUnauthorized => reverted;
    assert user == buyer => debtAfter <= debtBefore;
    assert user == seller => debtAfter >= debtBefore;
    assert user != buyer && user != seller => debtAfter == debtBefore;
}

rule withdrawCollateralDoesNotChangeDebt(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 assets, address onBehalf, address receiver, bytes32 id) {
    require noAccrual(e, id, onBehalf);

    mathint debtBefore = debtOf(id, onBehalf);

    withdrawCollateral(e, obligation, collateralIndex, assets, onBehalf, receiver);
    assert debtOf(id, onBehalf) == debtBefore;
}

rule repayDecreasesDebtByExactUnits(env e, Midnight.Obligation obligation, uint256 obligationUnits, address onBehalf, bytes32 id) {
    require noAccrual(e, id, onBehalf);

    mathint debtBefore = debtOf(id, onBehalf);

    repay(e, obligation, obligationUnits, onBehalf);
    mathint debtAfter = debtOf(id, onBehalf);

    // If debt changed at this id, it decreased by exactly obligationUnits.
    assert debtAfter != debtBefore => debtAfter + obligationUnits == debtBefore;
}
