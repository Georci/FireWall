pragma solidity ^0.8.20;

import "./IERC1967.sol";

interface ITransparentUpgradeableProxy is IERC1967 {
    function upgradeToAndCall(address, bytes calldata) external payable;
}
