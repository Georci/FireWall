// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract OracleIndex {
    address owner;
    
    modifier OnlyOwner() {
        require(tx.origin == owner, "forbiden access");
        _;
    }

    constructor(address _owner) {
        owner = _owner;
    }

    function register(address _targetPair) public OnlyOwner {

    }
}
