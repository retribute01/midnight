// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function _.price() external => NONDET;

    function tradingFee(bytes32, uint256) internal returns (uint256) => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function TickLib.wExp(int256) internal returns (uint256) => NONDET;
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;
    function UtilsLib.msb(uint256) internal returns (uint256) => NONDET;
    function UtilsLib.countBits(uint128) internal returns (uint256) => NONDET;

    function IdLib.toId(Midnight.Obligation memory, uint256, address) internal returns (bytes32) => NONDET;

    function accrueContinuousFee(Midnight.Obligation memory, bytes32 id, address user) internal => summaryAccrueContinuousFee(id, user);

    // Summarize slash so that its credit writes do not fire the credit hooks below.
    // Slash-before-credit correctness is verified separately in SlashBeforeBalance.spec.
    function slash(bytes32 id, address user) internal => summarySlash(id, user);
}

/// GHOSTS ///

/// Whether accrueContinuousFee was called for (id, user) in this transaction.
persistent ghost mapping(bytes32 => mapping(address => bool)) accrued;

/// Whether credit was stored before accrueContinuousFee was called for (id, user).
persistent ghost mapping(bytes32 => mapping(address => bool)) creditStoredBeforeAccrual;

/// Whether credit was loaded before accrueContinuousFee was called for (id, user).
persistent ghost mapping(bytes32 => mapping(address => bool)) creditLoadedBeforeAccrual;

/// SUMMARIES ///

/// Summary for accrueContinuousFee: just sets the accrued ghost flag.
/// The original function body is replaced, so its internal credit reads/writes do not fire hooks.
function summaryAccrueContinuousFee(bytes32 id, address user) {
    accrued[id][user] = true;
}

/// Summary for slash: no-op for this spec.
/// Slash writes credit based on the loss index; that invariant is checked in SlashBeforeBalance.spec.
/// Suppressing slash here prevents its credit writes from interfering with the accrual ordering hooks.
function summarySlash(bytes32 id, address user) { }

/// HOOKS ///

hook Sstore position[KEY bytes32 id][KEY address user].credit uint128 newVal (uint128 oldVal) {
    if (!accrued[id][user] && (currentContract.position[id][user].pendingFee > 0 || newVal > oldVal)) {
        creditStoredBeforeAccrual[id][user] = true;
    }
}

hook Sload uint128 val position[KEY bytes32 id][KEY address user].credit {
    if (!accrued[id][user] && currentContract.position[id][user].pendingFee > 0) {
        creditLoadedBeforeAccrual[id][user] = true;
    }
}

/// RULES ///

/// Check that credit is never stored before accrueContinuousFee is called when
/// there is remaining fee to realize or credit is being increased.
/// The SSTOREs of accrueContinuousFee and slash are ignored (see summaries above).
rule creditNotStoredBeforeAccrual(env e, method f, calldataarg args, bytes32 id, address user) filtered { f -> !f.isView } {
    require !accrued[id][user], "initialize the ghost variable";
    require !creditStoredBeforeAccrual[id][user], "initialize the ghost variable";

    f(e, args);

    assert !creditStoredBeforeAccrual[id][user], "credit was stored before accrueContinuousFee was called";
}

/// Check that credit is never loaded before accrueContinuousFee is called when
/// there is remaining fee to realize.
/// The SLOADs of accrueContinuousFee and slash are ignored (see summaries above).
rule creditNotLoadedBeforeAccrual(env e, method f, calldataarg args, bytes32 id, address user) filtered { f -> f.selector != sig:creditOf(bytes32, address).selector && f.selector != sig:slashAndAccrueView(Midnight.Obligation, address).selector } {
    require !accrued[id][user], "initialize the ghost variable";
    require !creditLoadedBeforeAccrual[id][user], "initialize the ghost variable";

    f(e, args);

    assert !creditLoadedBeforeAccrual[id][user], "credit was loaded before accrueContinuousFee was called";
}
