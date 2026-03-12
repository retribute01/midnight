// SPDX-License-Identifier: GPL-2.0-or-later

import "Midnight.spec";

methods {
    function feeRecipient() external returns (address) envfree;
    function toId(Midnight.Obligation obligation) external returns (bytes32) envfree;
    function isAuthorized(address authorizer, address authorized) external returns (bool) envfree;
}

function accruedContinuousFeeBefore(bytes32 id, address user, uint256 blockTimestamp, uint256 maturity) returns mathint {
    mathint lastAccrual = currentContract.borrowerState[id][user].lastContinuousFeeAccrual;
    mathint pendingFee = currentContract.borrowerState[id][user].pendingFee;

    if (lastAccrual == 0 || maturity <= lastAccrual) return 0;

    mathint accrualEnd = blockTimestamp < maturity ? blockTimestamp : maturity;
    return pendingFee * (accrualEnd - lastAccrual) / (maturity - lastAccrual);
}

use invariant noRemainingContinuousFeeWithoutDebt;

rule takeCannotChangeBothSharesAndDebt(env e, uint256 obligationShares, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof, bytes32 id, address user) {
    uint256 sharesBefore = sharesOf(id, user);
    uint256 debtBefore = debtOf(id, user);
    take(e, obligationShares, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, signature, root, proof);
    uint256 sharesAfter = sharesOf(id, user);
    uint256 debtAfter = debtOf(id, user);

    assert sharesAfter == sharesBefore || debtAfter == debtBefore;
}

/// SHARES CHANGE RULES ///

/// An unauthorized caller cannot change a user's shares except via take.
/// Assumes no reentrancy: callbacks (onBuy, onSell) and token transfers are not modeled as re-entering Midnight, so re-entrant share changes are not covered.
rule onlyAuthorizedCanChangeSharesExceptTake(env e, method f, calldataarg args, bytes32 id, address user) filtered { f -> f.selector != sig:take(uint256, address, address, bytes, address, Midnight.Offer, Midnight.Signature, bytes32, bytes32[]).selector } {
    bool userIsAuthorized = user == e.msg.sender || isAuthorized(user, e.msg.sender);
    bool passiveFeeWithdraw = user == Utils.passiveFeeRecipient() && e.msg.sender == feeRecipient() && f.selector == sig:withdraw(Midnight.Obligation, uint256, uint256, address, address).selector;

    uint256 sharesBefore = sharesOf(id, user);
    f(e, args);
    uint256 sharesAfter = sharesOf(id, user);

    assert userIsAuthorized || passiveFeeWithdraw || sharesAfter == sharesBefore;
}

/// In take, the caller must be authorized by the taker and only the seller's shares can decrease.
/// Assumes no reentrancy: the onBuy/onSell callbacks could re-enter take (or another function) and decrease a different user's shares.
rule takeOnlyAuthorizedSellerSharesDecrease(env e, uint256 obligationShares, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof, bytes32 id, address user) {
    address seller = offer.buy ? taker : offer.maker;
    bool takerUnauthorized = e.msg.sender != taker && !isAuthorized(taker, e.msg.sender);

    uint256 sharesBefore = sharesOf(id, user);
    take@withrevert(e, obligationShares, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, signature, root, proof);
    bool reverted = lastReverted;
    uint256 sharesAfter = sharesOf(id, user);

    assert takerUnauthorized => reverted;
    assert user == seller => sharesAfter <= sharesBefore;
    assert user != seller => sharesAfter >= sharesBefore;
}

/// DEBT CHANGE RULES ///

/// A user whose debt is zero can only become a borrower via take.
rule zeroDebtOnlyIncreasesViaTake(env e, method f, calldataarg args, bytes32 id, address user) {
    uint256 debtBefore = debtOf(id, user);

    requireInvariant noRemainingContinuousFeeWithoutDebt(id, user);

    f(e, args);

    assert debtBefore > 0 || debtOf(id, user) == 0 || f.selector == sig:take(uint256, address, address, bytes, address, Midnight.Offer, Midnight.Signature, bytes32, bytes32[]).selector;
}

/// Assumes no reentrancy: callbacks (onBuy, onSell) and token transfers are not modeled as re-entering Midnight, so re-entrant debt changes are not covered.
rule onlyAuthorizedCanChangeDebtExceptTakeAndLiquidate(env e, method f, calldataarg args, bytes32 id, address user) filtered { f -> f.selector != sig:liquidate(Midnight.Obligation, uint256, uint256, uint256, address, bytes).selector && f.selector != sig:take(uint256, address, address, bytes, address, Midnight.Offer, Midnight.Signature, bytes32, bytes32[]).selector } {
    bool userIsAuthorized = user == e.msg.sender || isAuthorized(user, e.msg.sender);

    uint256 debtBefore = debtOf(id, user);
    f(e, args);
    uint256 debtAfter = debtOf(id, user);

    assert userIsAuthorized || debtAfter == debtBefore;
}

/// In liquidate, only the borrower's debt can change, and any increase is bounded by accrued fee.
rule liquidateCanChangeDebt(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data, address user) {
    bytes32 id = toId(obligation);
    mathint debtBefore = debtOf(id, user);
    mathint accruedFeeBefore = accruedContinuousFeeBefore(id, borrower, e.block.timestamp, obligation.maturity);

    liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);
    mathint debtAfter = debtOf(id, user);

    assert user == borrower => debtAfter <= debtBefore + accruedFeeBefore;
    assert user != borrower => debtAfter == debtBefore;
}

/// In take, the caller must be authorized by the taker, and only the buyer's or seller's debt can change.
/// Assumes no reentrancy: the onBuy/onSell callbacks could re-enter take (or another function) and change a different user's debt.
rule takeOnlyAuthorizedCanChangeDebt(env e, uint256 obligationShares, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof, bytes32 id, address user) {
    address buyer = offer.buy ? offer.maker : taker;
    address seller = offer.buy ? taker : offer.maker;
    bool takerUnauthorized = e.msg.sender != taker && !isAuthorized(taker, e.msg.sender);

    uint256 debtBefore = debtOf(id, user);
    take@withrevert(e, obligationShares, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, signature, root, proof);
    bool reverted = lastReverted;
    uint256 debtAfter = debtOf(id, user);

    assert takerUnauthorized => reverted;
    assert user == seller => debtAfter >= debtBefore;
    assert user != buyer && user != seller => debtAfter == debtBefore;
}

rule withdrawCollateralDebtIncreasesByAccruedFee(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 assets, address onBehalf, address receiver) {
    bytes32 id = toId(obligation);
    mathint debtBefore = debtOf(id, onBehalf);
    mathint accruedFeeBefore = accruedContinuousFeeBefore(id, onBehalf, e.block.timestamp, obligation.maturity);

    withdrawCollateral(e, obligation, collateralIndex, assets, onBehalf, receiver);
    assert debtOf(id, onBehalf) == debtBefore + accruedFeeBefore;
}

rule repayDebtMatchesAccrualAndRepayment(env e, Midnight.Obligation obligation, uint256 obligationUnits, address onBehalf) {
    bytes32 id = toId(obligation);
    mathint debtBefore = debtOf(id, onBehalf);
    mathint accruedFeeBefore = accruedContinuousFeeBefore(id, onBehalf, e.block.timestamp, obligation.maturity);

    repay(e, obligation, obligationUnits, onBehalf);
    assert debtOf(id, onBehalf) + obligationUnits == debtBefore + accruedFeeBefore;
}
