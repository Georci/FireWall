// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import {ProxyForRouter} from "../proxy/proxyForRouter.sol";


contract SimpleSwap {
 uint256 reserveA;
 uint256 reserveB;
 ProxyForRouter router;
 

 constructor(address _routerProxy) {
    reserveA = 51;
    reserveB = 51;
    router = ProxyForRouter(payable(_routerProxy));
 }

 function test(uint256 value) public {
     bytes memory data = abi.encodeWithSignature(
            "executeWithDetect(bytes)",
            msg.data
        );
        router.CallOn(data);
    if (value < 10) {
        // 分支 1：value 小于 10，增加 reserveA
        reserveA -= value;
    } else if (value >= 10 && value < 100) {
    // 分支 2：value 在 10 到 99 之间，增加 reserveB
        reserveB -= value;
    } else {
        // 分支 4：value 大于等于 1000，将 reserveA 和 reserveB 重置为初始值
        reserveA = 0;
        reserveB = 0;
    }
 }

 function set(uint256 a,uint256 b) public{
    reserveA = a;
    reserveB = b;
    }
}
