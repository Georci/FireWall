// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (proxy/transparent/ProxyAdmin.sol)

pragma solidity ^0.8.20;

import {ITransparentUpgradeableProxy} from "./Interface/ITransparentUpgradeableProxy.sol";
import {Ownable} from "./access/Ownable.sol";

/**
 * @dev 辅助合约，旨在分配 {TransparentUpgradeableProxy} 的管理员。
 */
contract ProxyAdmin is Ownable {
    /**
     * @dev The version of the upgrade interface of the contract. If this getter is missing, both `upgrade(address,address)`
     * and `upgradeAndCall(address,address,bytes)` are present, and `upgrade` must be used if no function should be called,
     * while `upgradeAndCall` will invoke the `receive` function if the third argument is the empty byte string.
     * If the getter returns `"5.0.0"`, only `upgradeAndCall(address,address,bytes)` is present, and the third argument must
     * be the empty byte string if no function should be called, making it impossible to invoke the `receive` function
     * during an upgrade.
     */
    string public constant UPGRADE_INTERFACE_VERSION = "5.0.0";

    /**
     * @dev 设置可以执行升级的初始owner
     */
    constructor(address initialOwner) Ownable(initialOwner) {}

    /**
     * @dev 将代理升级到'implementation'上并调用新实现上的一个函数。
     *
     * 要求:
     * - 这个合约必须是代理的合约管理员。
     * - 如果data是空，msg.value必须为零。
     */
    function upgradeAndCall(
        ITransparentUpgradeableProxy proxy,
        address implementation,
        bytes memory data
    ) public payable virtual onlyOwner {
        proxy.upgradeToAndCall{value: msg.value}(implementation, data);
    }
}