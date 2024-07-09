//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {Test, console} from "forge-std/Test.sol";


contract AuthModule {
    //黑名单模式:1.函数黑名单 2.全局黑名单
    struct BlackMode {
        bool isFuctionAccessBlacklist;
        bool isGlobalAccessBlacklist;
    }
    // 黑名单 项目地址 => 函数选择器 => 黑名单地址 => 是否是黑名单 (避免遍历数组)
    mapping(address => mapping(bytes4 => mapping(address => bool))) functionAccessBlacklist;
    // 全局黑名单 项目地址 => 黑名单地址 => 是否是黑名单
    mapping(address => mapping(address => bool)) globalAccessBlacklist;
    // 项目地址 => 启用模式
    mapping(address => BlackMode) blackListMode;

    address manager;
    address router;
    address registry;
    // =============================修饰符=============================

    // 检查权限修饰符
    modifier check() {
        require(
            msg.sender == router ||
                msg.sender == registry ||
                msg.sender == manager,
            "ParamModule:permission denied"
        );
        _;
    }
    // =============================事件=============================

    // 黑名单地址访问事件
    event BlackAddrAccess(address project, address blackAddr);
    // 添加黑名单地址事件
    event AddBlackAddr(address project, address blackAddr);
    // 移除黑名单地址事件
    event RemoveBlackAddr(address project, address blackAddr);

    // 与代理直接进行交互
    constructor(address _routerProxy, address _registryProxy) {
        router = _routerProxy;
        registry = _registryProxy;
        manager = msg.sender;
    }

    // =============================管理函数=============================

    /**
     * @dev 改变项目方黑名单拦截策略，是否启用函数级别拦截
     * @param data 包含项目方地址project以及是否启用函数级别黑名单拦截_isFuctionAccessBlacklist
     */
    function changeMode(bytes memory data) external check {
        (address project, bool _isFuctionAccessBlacklist) = abi.decode(
            data,
            (address, bool)
        );
        if (
            blackListMode[project].isFuctionAccessBlacklist !=
            _isFuctionAccessBlacklist
        ) {
            blackListMode[project]
                .isFuctionAccessBlacklist = _isFuctionAccessBlacklist;
        }
    }

    /**
     * @dev 设置黑名单信息，如果是初次添加，则会额外设置防护模式，防护模式默认全局防护
     * @param data 包含函数选择器、黑名单地址的ABI编码数据以及该项目是否是黑名单地址
     * @notice 项目方有可能是对某些地址做全局防护，有可能是对某些地址做函数防护，所以useFunction应该要和地址绑定
     */
    function setInfo(bytes memory data) external check {
        // 添加
        (
            address project,
            bool _isFuctionAccessBlacklist,
            bytes4 funcSig,
            address blackAddr,
            bool isblack,
            bool useFunctionAccess
        ) = abi.decode(data, (address, bool, bytes4, address, bool, bool));
        if (blackListMode[project].isGlobalAccessBlacklist == false) {
            blackListMode[project].isGlobalAccessBlacklist = true;
            blackListMode[project]
                .isFuctionAccessBlacklist = _isFuctionAccessBlacklist;
        }

        // 如果当前项目启用了函数级别拦截，且对该地址使用
        if (
            blackListMode[project].isFuctionAccessBlacklist == true &&
            useFunctionAccess == true
        ) {
            functionAccessBlacklist[project][funcSig][blackAddr] = isblack;
        } else {
            // 1.项目没有启用函数级别防护 2.启用了函数防护但是没有对当前地址使用，而是直接使用全局防护
            globalAccessBlacklist[project][blackAddr] = isblack;
        }
        emit AddBlackAddr(project, blackAddr);
    }

    /**
     * @dev 该函数用来批量设置黑名单信息，但是仅仅只适用于项目方只开启了全局拦截
     * @param data 包括项目方地址以及该项目全局拦截的黑名单地址
     */
    function batchSetInfo(bytes memory data) external check {
        (address project, address[] memory blackAddr) = abi.decode(
            data,
            (address, address[])
        );
        if (blackListMode[project].isFuctionAccessBlacklist == false) {
            if (blackListMode[project].isGlobalAccessBlacklist == true) {
                for (uint i = 0; i < blackAddr.length; i++) {
                    globalAccessBlacklist[project][blackAddr[i]] = true;
                }
            }
        }
    }

    /**
     * @dev 移除黑名单信息
     * @param data 包含函数选择器、项目地址、黑名单地址的ABI编码数据以及该项目置为非黑名单
     * @notice 这个地方感觉可以把address从data分离出来作为一个参数，而不是通过硬编码传递
     */
    function removeInfo(bytes memory data) external check {
        // 移除
        (bytes4 funcSig, address project, address blackAddr) = abi.decode(
            data,
            (bytes4, address, address)
        );
        if (blackListMode[project].isFuctionAccessBlacklist == true) {
            functionAccessBlacklist[project][funcSig][blackAddr] = false;
        } else {
            globalAccessBlacklist[project][blackAddr] = false;
        }
        emit RemoveBlackAddr(project, blackAddr);
    }

    // =============================检测函数=============================

    /**
     * @dev 检测是否允许访问
     * @param project 项目地址
     * @param args 参数列表
     * @param data 函数调用数据
     * @return 是否允许访问
     */
    function detect(
        address project,
        string[] memory args,
        bytes memory data
    ) external returns (bool) {
        // 开启了函数调用检测
        if (blackListMode[project].isFuctionAccessBlacklist == true) {
            // 对调用者使用的函数防护以及全局防护
            if (
                functionAccessBlacklist[project][bytes4(data)][tx.origin] ==
                true
            ) {
                emit BlackAddrAccess(project, tx.origin);
                revert("detect:black address access Function forbidden");
            }

            if (globalAccessBlacklist[project][tx.origin] == true) {
                emit BlackAddrAccess(project, tx.origin);
                revert("detect:black address access Global forbidden");
            }
        } else {
            // 如果没有开启函数级别防护，直接使用全局防护
            if (globalAccessBlacklist[project][tx.origin] == true) {
                emit BlackAddrAccess(project, tx.origin);
                revert("detect:black address access Global forbidden");
            }
        }
        return true;
    }
}
