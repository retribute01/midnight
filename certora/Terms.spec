// SPDX-License-Identifier: GPL-2.0-or-later

/// METHODS ///

methods {
    function withdrawable(bytes32 id) external returns uint256 envfree;
    function totalAssets(bytes32 id) external returns (uint256) envfree;
    function totalShares(bytes32 id) external returns (uint256) envfree;
    function bondSharesOf(address owner, bytes32 id) external returns (uint256) envfree;
    function debtOf(address owner, bytes32 id) external returns (uint256) envfree;

    function _.transfer(address, uint256) external => DISPATCHER(true);
    function _.transferFrom(address, address, uint256) external => DISPATCHER(true);

    function _.price() external => NONDET;
}

/// HELPERS ///

persistent ghost mapping(bytes32 => mathint) sumBondSharesOf {
    init_state axiom (forall bytes32 id. sumBondSharesOf[id] == 0);
}
hook Sload uint256 bondSharesOfOwner bondSharesOf[KEY address owner][KEY bytes32 id] {
    require sumBondSharesOf[id] >= to_mathint(bondSharesOfOwner);
}
hook Sstore bondSharesOf[KEY address owner][KEY bytes32 id] uint256 newBondShares (uint256 oldBondShares) {
    sumBondSharesOf[id] = sumBondSharesOf[id] - oldBondShares + newBondShares;
}

persistent ghost mapping(bytes32 => mathint) sumDebtOf {
    init_state axiom (forall bytes32 id. sumDebtOf[id] == 0);
}
hook Sload uint256 debtOfOwner debtOf[KEY address owner][KEY bytes32 id] {
    require sumDebtOf[id] >= to_mathint(debtOfOwner);
}
hook Sstore debtOf[KEY address owner][KEY bytes32 id] uint256 newDebt (uint256 oldDebt) {
    sumDebtOf[id] = sumDebtOf[id] - oldDebt + newDebt;
}

/// SANITY ///

rule sanity() {
    assert true;
}

/// INVARIANTS ///

strong invariant totalAssetsEqualsSumDebtPlusWithdrawable(bytes32 id)
    totalAssets(id) == sumDebtOf[id] + withdrawable(id);

strong invariant totalSharesEqualsSumBondSharesOf(bytes32 id)
    totalShares(id) == sumBondSharesOf[id];

// this is not true because of the roundings in shares to/from assets conversions
// strong invariant sharePriceBelow1(bytes32 id)
//     totalShares(id) >= totalAssets(id);

// this is not true because of the roundings in shares to/from assets conversions
// invariant notBorrowerAndLender(bytes32 id, address user)
//     bondSharesOf(user, id) == 0 || debtOf(user, id) == 0;
