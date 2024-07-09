pragma solidity ^0.8.20;

import "./ERC1967Upgrade.sol";


// CALL Logic
contract ERC1967Proxy is ERC1967Upgrade{

    constructor(address _logic, bytes memory _data) payable {
        _upgradeToAndCall(_logic, _data, false);
    }

    function _implementation() internal view virtual returns (address impl) {
        return ERC1967Upgrade._getImplementation();
    }

    // 该函数负责调用逻辑合约中的函数，但是有个问题就是我们如果是对每个模块单独写一个代理合约的话，那就有点像代理之间的通信
    // 0x44是由于增加了
    function _delegate(address implementation) internal virtual {
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(
                gas(),
                implementation,
                0,
                calldatasize(),
                0,
                0
            )
            let size := returndatasize()
            returndatacopy(0, 0, size)
            switch result
            case 0 {
                revert(0, size)
            }
            default {
                return(0, size)
            }
        }
    }
    // 该函数负责调用逻辑合约中的函数，但是有个问题就是我们如果是对每个模块单独写一个代理合约的话，那就有点像代理之间的通信
    // 0x44是由于增加了
    function _delegate2(address implementation) internal virtual {
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(
                gas(),
                implementation,
                0x44,
                calldatasize(),
                0,
                0
            )
            let size := returndatasize()
            returndatacopy(0, 0, size)
            switch result
            case 0 {
                revert(0, size)
            }
            default {
                return(0, size)
            }
        }
    }

    function _beforeFallback() internal virtual {}

    function _fallback() internal {
        // _beforeFallback();
        _delegate(_implementation());
    }

    function _fallbackCallOn() internal {
        _delegate2(_implementation());
    }

    fallback() external payable {
        _fallback();
    }

    receive() external payable {
        _fallback();
    }
}
