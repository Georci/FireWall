pragma solidity ^0.8.20;

import "../../lib/forge-std/src/Test.sol";
import "./ERC1967Proxy.sol";
import "./ProxyAdmin.sol";

contract ProxyForRouter is ERC1967Proxy {
    constructor(
        address _logic,
        address admin_,
        bytes memory _data
    ) ERC1967Proxy(_logic, _data) {
        _changeAdmin(admin_);
    }

    modifier ifAdmin() {
        if (msg.sender == _getAdmin()) {
            _;
        } else {
            _fallback();
        }
    }

    // 这里的data有没有可能不需要
    // 调用防火墙的方法：1.CallOn 2.硬编码
    function CallOn(bytes memory _data) external {
        _fallbackCallOn();
    }

    /**
     * @dev Upgrade the implementation of the proxy.
     * @param newImplementation new Logic Address.
     * NOTE: Only the admin can call this function. See {ProxyAdmin-upgrade}.
     */
    function upgradeTo(address newImplementation) external ifAdmin {
        _upgradeToAndCall(newImplementation, bytes(""), false);
    }

    /**
     * @dev 升级合约的同时，使用data去调用Logic contract.
     * NOTE: Only the admin can call this function. See {ProxyAdmin-upgradeAndCall}.
     */
    function upgradeToAndCall(
        address newImplementation,
        bytes calldata data
    ) external payable ifAdmin {
        _upgradeToAndCall(newImplementation, data, true);
    }
}
