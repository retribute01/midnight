// SPDX-License-Identifier: GPL-2.0-or-later

/// METHODS ///

methods {
    function withdrawable(bytes32 id) external returns uint256 envfree;
    
    function _.transferFrom(address, address, uint256) external => HAVOC_ECF;
    function _.transfer(address, uint256) external => HAVOC_ECF;
}

/// HOOKS ///

persistent ghost mapping(bytes32 => mathint) sumBondOf {
    init_state axiom (forall bytes32 id. sumBondOf[id] == 0);
}
hook Sload uint256 bondOfOwner bondOf[KEY address owner][KEY bytes32 id] {
    require sumBondOf[id] >= to_mathint(bondOfOwner);
}
hook Sstore bondOf[KEY address owner][KEY bytes32 id] uint256 newBond (uint256 oldBond) {
    sumBondOf[id] = sumBondOf[id] - oldBond + newBond;
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

invariant sanitySumBond(bytes32 id)
    sumBondOf[id] >= 0;
    
invariant sanitySumDebt(bytes32 id)
    sumDebtOf[id] >= 0;
    

rule satisfyMint(env e, calldataarg args) {
    mint(e, args);
    satisfy true;
}

rule satisfyTransferDebt(env e, calldataarg args) {
    transferDebt(e, args);
    satisfy true;
}

rule satisfyTransferBond(env e, calldataarg args) {
    transferBond(e, args);
    satisfy true;
}

/// INVARIANTS ///

invariant sums(bytes32 id)
    sumBondOf[id] == sumDebtOf[id] + withdrawable(id);
