methods {
    function mulDivDown(uint256 a, uint256 b, uint256 d) external returns (uint256) envfree;
    function mulDivUp(uint256 a, uint256 b, uint256 d) external returns (uint256) envfree;
}

/// RULES ///

/* these proves the axiom used in the other specs */

rule zeroMulDiv(uint256 b, uint256 d) {
    assert mulDivDown(0, b, d) == 0;
    assert mulDivUp(0, b, d) == 0;
}

rule monotoneMulDiv(uint256 a1, uint256 a2, uint256 b, uint256 d) {
    require a1 <= a2 && d > 0, "preconditions";
    assert mulDivDown(a1, b, d) <= mulDivDown(a2, b, d);
    assert mulDivUp(a1, b, d) <= mulDivUp(a2, b, d);
}

rule addMulDiv(uint256 a1, uint256 a2, uint256 b, uint256 d) {
    require d > 0, "preconditions";
    uint256 a1plusa2 = require_uint256(a1 + a2);
    assert mulDivDown(a1, b, d) + mulDivDown(a2, b, d) <= mulDivDown(a1plusa2, b, d);
    assert mulDivUp(a1, b, d) + mulDivUp(a2, b, d) >= mulDivUp(a1plusa2, b, d);
}

rule subtractMulDiv(uint256 a1, uint256 a2, uint256 b, uint256 d) {
    require a1 <= a2 && d > 0, "preconditions";
    uint256 a2minusa1 = assert_uint256(a2 - a1);
    assert mulDivDown(a2minusa1, b, d) <= mulDivDown(a2, b, d) - mulDivDown(a1, b, d);
    assert mulDivUp(a2minusa1, b, d) >= mulDivUp(a2, b, d) - mulDivUp(a1, b, d);
}

rule subtractMulDiv2(uint256 a1, uint256 a2, uint256 b, uint256 d) {
    require a1 <= a2 && d > 0, "preconditions";
    uint256 a2minusa1 = assert_uint256(a2 - a1);
    assert mulDivDown(a2minusa1, b, d) >= mulDivDown(a2, b, d) - mulDivUp(a1, b, d);
}

rule inverseMulDiv(uint256 a, uint256 b, uint256 d) {
    require b > 0 && d > 0, "preconditions";
    assert a <= mulDivDown(mulDivUp(a, b, d), d, b);
    assert mulDivUp(mulDivDown(a, b, d), d, b) <= a;
}

