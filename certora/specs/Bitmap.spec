// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function getBit(uint256 bitmap, uint256 bit) external returns (bool) envfree;
    function setBit(uint256 bitmap, uint256 bit) external returns (uint256) envfree;
    function clearBit(uint256 bitmap, uint256 bit) external returns (uint256) envfree;
    function msb(uint256 bitmap) external returns (uint256) envfree;
}

/// RULES ///

rule zeroBitmapEmpty(uint256 bit) {
    bool isBitSet = getBit(0, bit);
    assert !isBitSet, "zero bitmap has no bit set";
}

rule getBitmapOutOfRange(uint128 bitmap, uint256 bit) {
    bool isBitSet = getBit(bitmap, bit);
    assert bit >= 128 => !isBitSet, "bitmap is limited to 128 bits";
}

rule setBitSetsBit(uint128 bitmap, uint256 bit) {
    uint256 otherBit;
    require bit < 128, "bitmap is limited to 128 bits";
    require otherBit < 128, "bitmap is limited to 128 bits";

    bool otherBefore = getBit(bitmap, otherBit);

    uint256 bitmapAfter = setBit(bitmap, bit);
    bool otherAfter = getBit(bitmapAfter, otherBit);
    bool bitAfter = getBit(bitmapAfter, bit);

    assert bitAfter, "setBit sets the bit";
    assert otherBit != bit => otherBefore == otherAfter, "setBit doesn't change other bits";
    assert bitmapAfter < 2 ^ 128, "result fits in 128 bit";
}

rule clearBitClearsBit(uint128 bitmap, uint256 bit) {
    uint256 otherBit;
    require bit < 128, "bitmap is limited to 128 bits";
    require otherBit < 128, "bitmap is limited to 128 bits";

    bool otherBefore = getBit(bitmap, otherBit);

    uint256 bitmapAfter = clearBit(bitmap, bit);
    bool otherAfter = getBit(bitmapAfter, otherBit);
    bool bitAfter = getBit(bitmapAfter, bit);

    assert !bitAfter, "clearBit clears the bit";
    assert otherBit != bit => otherBefore == otherAfter, "clearBit doesn't change other bits";
    assert bitmapAfter < 2 ^ 128, "result fits in 128 bit";
}

rule msbReturnsLargestSetBit(uint128 bitmap) {
    uint256 msbBit = msb(bitmap);
    uint256 otherBit;

    assert bitmap == 0 => msbBit == 2 ^ 256 - 1;
    assert bitmap != 0 => msbBit < 128;
    assert bitmap != 0 => getBit(bitmap, msbBit);
    assert bitmap != 0 && getBit(bitmap, otherBit) => otherBit <= msbBit;
}
