// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

contract ERC20 {
    string public name;
    string public symbol;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;

    constructor(string memory _name, string memory _symbol, uint256 _totalSupply) {
        name = _name;
        symbol = _symbol;
        totalSupply = _totalSupply;
        balanceOf[msg.sender] = _totalSupply;
    }

    function transfer(address recipient, uint256 amount) public returns (bool) {
        require(amount <= balanceOf[msg.sender], "Insufficient balance");

        balanceOf[msg.sender] -= amount;
        balanceOf[recipient] += amount;

        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public returns (bool) {
        require(amount <= balanceOf[sender], "Insufficient balance");

        balanceOf[sender] -= amount;
        balanceOf[recipient] += amount;

        return true;
    }
}
