// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function creditOf(bytes32 id, address user) external returns (uint256) envfree;
    function debtOf(bytes32 id, address user) external returns (uint256) envfree;
    function consumed(address user, bytes32 group) external returns (uint256) envfree;
    function session(address user) external returns (bytes32) envfree;
    function isAuthorized(address authorizer, address authorized) external returns (bool) envfree;

    // Summarize internal functions that use opcodes causing HAVOC (CREATE2, low-level calls).
    function IdLib.storeInCode(Midnight.Obligation memory) internal returns (address) => NONDET;
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;

    // Summarize complex internals irrelevant to credit and debt tracking.
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function TickLib.wExp(int256) internal returns (uint256) => NONDET;

    function tradingFee(bytes32, uint256) internal returns (uint256) => NONDET;

    function isHealthy(Midnight.Obligation memory, bytes32, address) internal returns (bool) => NONDET;

    // Assume no reentrancy: callbacks do not re-enter Midnight.
    function _.onBuy(Midnight.Obligation, address, uint256, uint256, uint256, bytes) external => NONDET;
    function _.onSell(Midnight.Obligation, address, uint256, uint256, uint256, bytes) external => NONDET;
    function _.onFlashLoan(address, uint256, bytes) external => NONDET;

    function signer(bytes32, Midnight.Signature memory) internal returns (address) => CVL_signer();
}

/// HELPERS ///

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
rule onlyAuthorizedCanChangeCreditAndDebtExceptLiquidateAndSlash(env e, method f, calldataarg args, bytes32 id, address user) filtered { f -> !f.isView && f.selector != sig:liquidate(Midnight.Obligation, uint256, uint256, uint256, address, bytes).selector && f.selector != sig:slash(bytes32, address).selector } {
    bool userIsAuthorized = user == e.msg.sender || isAuthorized(user, e.msg.sender);

    uint256 creditBefore = creditOf(id, user);
    uint256 debtBefore = debtOf(id, user);
    f(e, args);
    uint256 creditAfter = creditOf(id, user);
    uint256 debtAfter = debtOf(id, user);

    assert (creditAfter == creditBefore && debtAfter == debtBefore) || userIsAuthorized || signed[user];
}

/// CONSUMED CHANGE RULES ///

/// An unauthorized caller cannot change a user's consumed except via take.
/// Assumes no reentrancy: callbacks and token transfers are not modeled as re-entering Midnight, so re-entrant consumed changes are not covered.
rule onlyAuthorizedCanChangeConsumedExceptTake(env e, method f, calldataarg args, address user, bytes32 group) filtered { f -> !f.isView && f.selector != sig:take(uint256, address, address, bytes, address, Midnight.Offer, Midnight.Signature, bytes32, bytes32[]).selector } {
    bool userIsAuthorized = user == e.msg.sender || isAuthorized(user, e.msg.sender);

    uint256 consumedBefore = consumed(user, group);
    f(e, args);
    uint256 consumedAfter = consumed(user, group);

    assert userIsAuthorized || consumedAfter == consumedBefore;
}

/// In take, only the maker's consumed can change.
rule takeCanChangeConsumed(env e, uint256 obligationShares, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof, address user, bytes32 group) {
    uint256 consumedBefore = consumed(user, group);
    take(e, obligationShares, taker, takerCallback, takerCallbackData, receiverIfTakerIsSeller, offer, signature, root, proof);
    uint256 consumedAfter = consumed(user, group);

    assert user != offer.maker || group != offer.group => consumedAfter == consumedBefore;
    assert consumedAfter >= consumedBefore;
}

/// SESSION CHANGE RULES ///

/// An unauthorized caller cannot change a user's session.
rule onlyAuthorizedCanChangeSession(env e, method f, calldataarg args, address user) filtered { f -> !f.isView } {
    bool userIsAuthorized = user == e.msg.sender || isAuthorized(user, e.msg.sender);

    bytes32 sessionBefore = session(user);
    f(e, args);
    bytes32 sessionAfter = session(user);

    assert userIsAuthorized || sessionAfter == sessionBefore;
}

/// AUTHORIZATION CHANGE RULES ///

/// An unauthorized caller cannot change a user's isAuthorized mapping.
rule onlyAuthorizedCanChangeIsAuthorized(env e, method f, calldataarg args, address authorizer, address authorized) filtered { f -> !f.isView } {
    bool authorizerIsAuthorized = authorizer == e.msg.sender || isAuthorized(authorizer, e.msg.sender);

    bool isAuthorizedBefore = isAuthorized(authorizer, authorized);
    f(e, args);
    bool isAuthorizedAfter = isAuthorized(authorizer, authorized);

    assert authorizerIsAuthorized || isAuthorizedAfter == isAuthorizedBefore;
}
