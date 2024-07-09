pragma solidity ^0.8.20;

import "./ERC1967Proxy.sol";

contract ProxyForRegistry is ERC1967Proxy {
    constructor(
        address _logic,
        address admin_,
        bytes memory _data
    ) payable ERC1967Proxy(_logic, _data) {
        _changeAdmin(admin_);
    }

    modifier ifAdmin() {
        if (msg.sender == _getAdmin()) {
            _;
        } else {
            _fallback();
        }
    }

    function CallOn(bytes memory _data) external {
        _fallbackCallOn();
    }

    /**
     * @dev 升级逻辑合约
     * @param newImplementation new Logic Address.
     */
    function upgradeTo(address newImplementation) external ifAdmin {
        _upgradeToAndCall(newImplementation, bytes(""), false);
    }

    /**
     * @dev 升级合约的同时，使用data去调用Logic contract.
     */
    function upgradeToAndCall(
        address newImplementation,
        bytes calldata data
    ) external payable ifAdmin {
        _upgradeToAndCall(newImplementation, data, true);
    }
}
