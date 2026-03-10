// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function collateralOf(bytes32 id, address user, uint256) external returns (uint128) envfree;
    function collateralBitSet(bytes32, address, uint256) external returns (bool) envfree;
    function isHealthy(Midnight.Obligation, bytes32, address) external returns (bool) envfree;
    function isHealthyNoBitmap(Midnight.Obligation, bytes32, address) external returns (bool) envfree;

    function _.price() external => summaryPrice(calledContract) expect(uint256);
    function TickLib.tickToPrice(uint256 tick) internal returns (uint256) => NONDET;
    function IdLib.toId(Midnight.Obligation memory obligation, uint256 chainId, address morpho) internal returns (bytes32) => NONDET;
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivDown(x, y, d);
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => summaryMulDivUp(x, y, d);
}

/// SUMMARY ///

persistent ghost summaryPrice(address) returns uint256;

persistent ghost summaryMulDivDown(uint256, uint256, uint256) returns uint256 {
    /* proved in mulDivZero in MulDiv.spec */
    axiom forall uint256 b. forall uint256 d. d > 0 => summaryMulDivDown(0, b, d) == 0;
}

persistent ghost summaryMulDivUp(uint256, uint256, uint256) returns uint256 {
    /* proved in mulDivZero in MulDiv.spec */
    axiom forall uint256 b. forall uint256 d. d > 0 => summaryMulDivUp(0, b, d) == 0;
}

invariant bitsetIffCollateral(bytes32 id, address borrower, uint256 idx)
    idx < 128 => (collateralBitSet(id, borrower, idx) <=> collateralOf(id, borrower, idx) != 0);

rule isHealthyEquivalant(Midnight.Obligation obligation, bytes32 id, address borrower) {
    // We restrict to at most three collaterals
    require obligation.collaterals.length <= 3, "restrict to three collaterals";
    requireInvariant bitsetIffCollateral(id, borrower, 0);
    requireInvariant bitsetIffCollateral(id, borrower, 1);
    requireInvariant bitsetIffCollateral(id, borrower, 2);

    bool isHealthy1 = isHealthy@withrevert(obligation, id, borrower);
    require !lastReverted;
    bool isHealthy2 = isHealthyNoBitmap@withrevert(obligation, id, borrower);
    assert !lastReverted;

    assert isHealthy1 == isHealthy2;
}
