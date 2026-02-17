// SPDX-License-Identifier: GPL-2.0-or-later

using IdSummary as IdSummary;
using MorphoV2 as MorphoV2;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;
    function _.price() external => NONDET;

    function IdSummary.toIdSummary(MorphoV2.Obligation, uint256, address) external returns (bytes32) envfree;
    function MorphoV2.obligationCreated(bytes32) external returns (bool) envfree;

    function IdLib.toId(MorphoV2.Obligation memory obligation, uint256, address) internal returns (bytes32) => summaryToId(obligation);

    function UtilsLib.mulDivDown(uint256, uint256, uint256) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivUp(uint256, uint256, uint256) internal returns (uint256) => NONDET;
}

function summaryToId(MorphoV2.Obligation obligation) returns (bytes32) {
    return IdSummary.toIdSummary(obligation, 0, 0);
}

invariant createdObligationsHaveSortedCollaterals(MorphoV2.Obligation obligation, uint256 i, uint256 j)
    MorphoV2.obligationCreated(summaryToId(obligation)) => i < j => j < obligation.collaterals.length => obligation.collaterals[i].token < obligation.collaterals[j].token;
