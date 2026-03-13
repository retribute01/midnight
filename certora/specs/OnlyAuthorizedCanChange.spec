// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function balanceOf(bytes32 id, address user) external returns (int256) envfree;
    function debtOf(bytes32 id, address user) external returns (uint256) envfree;
    function isAuthorized(address authorizer, address authorized) external returns (bool) envfree;

    function _.price() external => NONDET;

    // Summarize mulDivDown and mulDivUp by ghost functions. This is for performance of the prover.
    function UtilsLib.mulDivDown(uint256 a, uint256 b, uint256 denominator) internal returns (uint256) => CVL_mulDivDown(a, b, denominator);
    function UtilsLib.mulDivUp(uint256 a, uint256 b, uint256 denominator) internal returns (uint256) => CVL_mulDivUp(a, b, denominator);
    function UtilsLib.negativePart(int256 x) internal returns (uint256) => CVL_negativePart(x);

    // Summarize internal functions that use opcodes causing HAVOC (CREATE2, low-level calls).
    function IdLib.storeInCode(Midnight.Obligation memory) internal returns (address) => NONDET;
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;

    // Summarize complex internals irrelevant to balance tracking.
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;
    function UtilsLib.msb(uint256) internal returns (uint256) => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function TickLib.wExp(int256) internal returns (uint256) => NONDET;
    function isHealthy(Midnight.Obligation memory, bytes32, address) internal returns (bool) => NONDET;
    function tradingFee(bytes32, uint256) internal returns (uint256) => NONDET;

    // Assume no reentrancy: callbacks and token transfers do not re-enter Midnight.
    function _.onBuy(Midnight.Obligation, address, uint256, uint256, uint256, bytes) external => NONDET;
    function _.onSell(Midnight.Obligation, address, uint256, uint256, uint256, bytes) external => NONDET;
    function _.onLiquidate(Midnight.Obligation, uint256, uint256, uint256, address, bytes) external => NONDET;
    function _.onFlashLoan(address, uint256, bytes) external => NONDET;
    function _.transfer(address, uint256) external => NONDET;
    function _.transferFrom(address, address, uint256) external => NONDET;
}

/// HELPERS ///

function CVL_mulDivDown(uint256 x, uint256 y, uint256 d) returns uint256 {
    if (x == 0 || y == 0) return 0;
    if (d > 0 && y == d) return x;
    if (d > 0 && x == d) return y;
    uint256 res;
    if (d > 0) {
        require to_mathint(res) * to_mathint(d) <= to_mathint(x) * to_mathint(y);
    }
    return res;
}

function CVL_mulDivUp(uint256 x, uint256 y, uint256 d) returns uint256 {
    if (x == 0 || y == 0) return 0;
    if (d > 0 && y == d) return x;
    if (d > 0 && x == d) return y;
    uint256 res;
    return res;
}

function CVL_negativePart(int256 x) returns uint256 {
    return x < 0 ? require_uint256(-to_mathint(x)) : 0;
}

/// BALANCE CHANGE RULES ///

/// An unauthorized caller cannot change a user's balance except via take, liquidate, and slash.
/// Assumes no reentrancy: callbacks (onBuy, onSell) and token transfers are not modeled as re-entering Midnight, so re-entrant balance changes are not covered.
rule onlyAuthorizedCanChangeBalanceExceptTakeLiquidateAndSlash(env e, method f, calldataarg args, bytes32 id, address user) filtered { f -> f.selector != sig:take(uint256, address, address, bytes, address, Midnight.Offer, Midnight.Signature, bytes32, bytes32[]).selector && f.selector != sig:liquidate(Midnight.Obligation, uint256, uint256, uint256, address, bytes).selector && f.selector != sig:slash(bytes32, address).selector } {
    bool userIsAuthorized = user == e.msg.sender || isAuthorized(user, e.msg.sender);

    int256 balanceBefore = balanceOf(id, user);
    f(e, args);
    int256 balanceAfter = balanceOf(id, user);

    assert userIsAuthorized || balanceAfter == balanceBefore;
}

/// In take, the caller must be authorized by the taker. The seller's balance can only decrease, and non-participants' balance is unchanged.
/// Assumes no reentrancy: the onBuy/onSell callbacks could re-enter take (or another function) and change a different user's balance.
rule takeOnlyAuthorizedCanChangeBalance(env e, uint256 obligationUnits, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof, bytes32 id, address user) {
    // Safe cast: obligationUnits must fit in int256 to avoid wrapping in the contract's int256(obligationUnits) cast.
    require obligationUnits < 2 ^ 255;

    // Loss index is monotonically increasing, so slash can only decrease positive balances.
    require forall bytes32 _id. forall address _user. currentContract.obligationState[_id].lossIndex >= currentContract.userLossIndex[_id][_user];

    address seller = offer.buy ? taker : offer.maker;
    address buyer = offer.buy ? offer.maker : taker;
    bool takerIsAuthorized = e.msg.sender == taker || isAuthorized(taker, e.msg.sender);

    int256 balanceBefore = balanceOf(id, user);
    take(e, obligationUnits, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, signature, root, proof);
    int256 balanceAfter = balanceOf(id, user);

    assert takerIsAuthorized;
    assert user == seller => balanceAfter <= balanceBefore;
    assert user != buyer && user != seller => balanceAfter == balanceBefore;
}

/// DEBT CHANGE RULES ///

/// In take, the buyer's debt can only decrease, the seller's debt can only increase, and non-participants' debt is unchanged.
/// Assumes no reentrancy: the onBuy/onSell callbacks could re-enter take (or another function) and change a different user's debt.
rule takeOnlyAuthorizedCanChangeDebt(env e, uint256 obligationUnits, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof, bytes32 id, address user) {
    // Safe cast: obligationUnits must fit in int256 to avoid wrapping in the contract's int256(obligationUnits) cast.
    require obligationUnits < 2 ^ 255;

    // Loss index is monotonically increasing, so slash can only decrease positive balances.
    require forall bytes32 _id. forall address _user. currentContract.obligationState[_id].lossIndex >= currentContract.userLossIndex[_id][_user];

    address buyer = offer.buy ? offer.maker : taker;
    address seller = offer.buy ? taker : offer.maker;
    bool takerIsAuthorized = e.msg.sender == taker || isAuthorized(taker, e.msg.sender);

    uint256 debtBefore = debtOf(id, user);
    take(e, obligationUnits, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, signature, root, proof);
    uint256 debtAfter = debtOf(id, user);

    assert takerIsAuthorized;
    assert user == buyer => debtAfter <= debtBefore;
    assert user == seller => debtAfter >= debtBefore;
    assert user != buyer && user != seller => debtAfter == debtBefore;
}

/// In liquidate, the borrower's debt can only decrease, and non-borrowers' debt is unchanged.
rule liquidateCanChangeDebt(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data, bytes32 id, address user) {
    uint256 debtBefore = debtOf(id, user);
    liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);
    uint256 debtAfter = debtOf(id, user);

    assert user == borrower => debtAfter <= debtBefore;
    assert user != borrower => debtAfter == debtBefore;
}
