//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {FireWallRegistry} from "./Registry.sol";
import {Test, console} from "../../lib/forge-std/src/Test.sol";

contract ParamCheckModule {
    struct ParamRange {
        // 范围型拦截参数
        mapping(uint256 => uint256) rangeBlackParam;
        uint256[] rangeStart;
        // 存储离散型拦截参数
        mapping(uint256 => uint256) discreteBlackParam;
    }

    // 项目地址 => 函数 => 参数位置 => 参数范围
    mapping(address => mapping(bytes4 => mapping(uint64 => ParamRange))) paramRanges;
    // 参数是否注册(项目地址 => 函数 => 参数位置 => 该参数是否注册)
    mapping(address => mapping(bytes4 => mapping(uint64 => bool))) isRegister;
    address router;
    address manager;
    address registry;

    // =============================修饰符=============================
    modifier check() {
        console.log("check ", msg.sender);
        require(
            msg.sender == router ||
                msg.sender == registry ||
                msg.sender == manager,
            "ParamModule:permission denied"
        );
        _;
    }

    // =============================事件=============================
    event errorParam(address project, bytes4 sig, uint64 index, uint256 value); // 参数错误事件
    event setParamRange(
        address project,
        bytes4 sig,
        uint64 index,
        uint256 min,
        uint256 max
    ); // 设置参数范围事件
    event removeGobalParamRange(address project, bytes4 sig, uint64 index); // 移除某个参数全部拦截范围事件
    event removeSpecificParamRange(
        address project,
        bytes4 sig,
        uint64 index,
        uint256 min,
        bool isDiscrete
    ); // 移除某个参数特定的(部分的)拦截范围

    // registry、router都是通过与其proxy交互
    constructor(address _routerProxy, address _registryProxy) {
        router = _routerProxy;
        registry = _registryProxy;
        manager = msg.sender;
    }

    /**
     * @dev 设置参数范围
     * @param data 参数数据，被保护项目具体的函数保护信息
     */
    function setInfo(bytes memory data) external check {
        (
            address project,
            bytes4 sig,
            uint64 index,
            uint256 min,
            uint256 max,
            bool isDiscrete
        ) = abi.decode(data, (address, bytes4, uint64, uint256, uint256, bool));

        // 只有当传入的值是离散值，全部作为min处理
        if (isDiscrete == true && max == 0) {
            uint256 arrayIndex = min / 256;
            uint256 bitPosition = min % 256;
            uint256 bitMask = 1 << bitPosition;
            paramRanges[project][sig][index].discreteBlackParam[
                arrayIndex
            ] ^= bitMask;
        } else {
            paramRanges[project][sig][index].rangeBlackParam[min] = max;
            paramRanges[project][sig][index].rangeStart.push(min);
        }
        isRegister[project][sig][index] = true;
        emit setParamRange(project, sig, index, min, max);
    }

    /**
     * @dev 移除某个函数中特定位置参数全部的拦截参数
     * @param data 参数数据
     * @notice 这个地方我注意到如果一个函数的某个参数其拦截范围是离散的是不是需要移除其中一个范围的业务
     */
    function removeInfo(bytes memory data) external check {
        (bytes4 sig, address project, uint64 index) = abi.decode(
            data,
            (bytes4, address, uint64)
        );
        emit removeGobalParamRange(project, sig, index);
        delete paramRanges[project][sig][index];
    }

    /**
     * @dev 移除某个函数中特定位置参数部分的拦截参数
     * @dev 如果是离散参数，则移除min，如果是连续参数，则移除[min,max]
     * @param data 参数数据
     */
    function removePartialInfo(bytes memory data) external check {
        (
            bytes4 sig,
            address project,
            uint64 index,
            uint256 min,
            bool isDiscrete
        ) = abi.decode(data, (bytes4, address, uint64, uint256, bool));
        if (isDiscrete == true) {
            uint256 arrayIndex = min / 256;
            uint256 bitPosition = min % 256;
            uint256 bitMask = 1 << bitPosition;
            if (
                paramRanges[project][sig][index].discreteBlackParam[arrayIndex] & bitMask != 0
            ) {
                paramRanges[project][sig][index].discreteBlackParam[
                        arrayIndex
                    ] &= ~bitMask;
                emit removeSpecificParamRange(project, sig, index, min, true);
            }
        } else {
            uint256 length = paramRanges[project][sig][index].rangeStart.length;
            // 删除rangeStart中的元素
            for (uint64 i = 0; i < length; i++) {
                if (paramRanges[project][sig][index].rangeStart[i] == min) {
                    paramRanges[project][sig][index].rangeStart[
                        i
                    ] = paramRanges[project][sig][index].rangeStart[length - 1];
                    paramRanges[project][sig][index].rangeStart.pop();
                }
            }
            emit removeSpecificParamRange(project, sig, index, min, false);
            // 删除rangeStart中元素对应的最大值
            delete paramRanges[project][sig][index].rangeBlackParam[min];
        }
    }

    /**
     * @dev 检测参数是否在范围内
     * @param project 项目地址
     * @param args 参数类型数组
     * @param data 参数数据
     * @return 是否在范围内
     * @notice 拦截的逻辑,由于调用该函数的当前参数一定是单个值，所以我们没法判断是利用范围值对其拦截还是使用离散值对其拦截
     * 1.先在rangStart数组里面查找：应该是遍历rangStart数组，然后对于每一个最小值取出其mapping对应的最大值，然后将输入的值与每一个最小值与最大值进行比较
     * 2.离散的mapping里面查找，位图查找法，先除256，后对256取余，再将1左移余数位与原位图做异或
     */
    function detect(
        address project,
        string[] memory args,
        bytes memory data
    ) external returns (bool) {
        // 权限控制
        require(
            msg.sender == router,
            "ParamModule:detect only router can call"
        );
        // 参数长度不匹配
        require(data.length == args.length * 32 + 4, "error data length");
        // 遍历当前函数的全部参数
        for (uint64 i = 0; i < args.length; i++) {
            ParamRange storage range = paramRanges[project][bytes4(data)][i];
            // 判断当前参数是否注册
            if (isRegister[project][bytes4(data)][i] == false) {
                continue;
            }
            // 仅支持uint256
            if (keccak256(bytes(args[i])) == keccak256("uint256")) {
                bytes32 temp;
                // 读取传入的参数值
                assembly {
                    temp := mload(add(data, add(4, mul(add(i, 1), 32))))
                }

                uint256 value = uint256(temp);
                console.log("========================================");
                console.log("The param is:", value);
                console.log("========================================");
                // 离散参数
                uint256 arrayIndex = value / 256;
                uint256 bitPosition = value % 256;
                uint256 bitMask = 1 << bitPosition;
                if (range.discreteBlackParam[arrayIndex] & bitMask != 0) {
                    emit errorParam(project, bytes4(data), i, value);
                    revert("detect:error param");
                }
                // 范围参数
                for (uint64 j; j < range.rangeStart.length; j++) {
                    uint256 minValue = range.rangeStart[j];
                    uint256 maxValue = range.rangeBlackParam[minValue];
                    if (value >= minValue && value <= maxValue) {
                        emit errorParam(project, bytes4(data), i, value);
                        revert("detect:error param");
                    }
                }
            }
        }
        return true;
    }
}
