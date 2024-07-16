// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Interface/IModule.sol";
import "./Interface/IAuthenicationModule.sol";
import "./Interface/IParamCheckModule.sol";
import {Test, console} from "../../lib/forge-std/src/Test.sol";

/**
 * @title FireWallRegistry
 * @dev 用于保护函数和管理模块的注册表合约。
 */

// TODO:已经注册项目没有保存？
contract FireWallRegistry {
    // 注册表的管理者
    address owner;
    // 项目地址 => 项目管理者
    mapping(address => address) projectManagers;

    // 函数级别的映射
    struct ProtectInfo {
        // 参数类型
        string[] params;
        // 启用模块
        address[] enableModules;
        bool is_pause;
    }

    struct ModuleInfo {
        address modAddress;
        address modAdmin;
        string description;
        bool enable;
    }

    // 项目地址 => 函数选择器 => ProtectInfo
    // *存在问题，当需要返回project保护的所有函数的列表时，无法直接返回，因此增加了一个映射
    mapping(address => mapping(bytes4 => ProtectInfo)) protectFuncRegistry;
    mapping(address => bytes4[]) protectFuncSet; // 项目地址 => 保护函数的数组

    // 模块数组
    // *存在查询不便的问题，因此需要增加一个地址到模块名称的映射以及一个模块地址到模块索引的映射
    ModuleInfo[] moduleInfos;
    mapping(address => string) public moduleNames; // 模块地址 => 模块名称
    mapping(address => uint64) public moduleIndex; // 模块地址 => 模块索引

    // 暂停交互的项目列表
    mapping(address => bool) public pauseMap;

    // =============================Modifiers=============================

    /**
     * @dev 仅允许所有者调用的修饰符。
     */
    modifier onlyOwner() {
        require(msg.sender == owner, "only owner can call");
        _;
    }

    // =============================Events=============================

    event RegisterInfo(
        address project,
        bytes4 funcSig,
        address manager,
        string[] params,
        address[] enableModules
    );
    event AddModule(
        address detectModAddr,
        address detectModAdmin,
        string module_description,
        bool enable
    );
    event UpdateModuleInfo(string module_name);
    event RemoveModuleInfo(string module_name);
    event PauseModule(address module_address);
    event UnpauseModule(address module_address);
    event PauseDetect();
    event RemoveModuleForProject(
        address project,
        bytes4 funcSig,
        string module_description,
        address module_address
    );
    event RemoveModule(string module_description, address module_address);
    event pauseProjectInteract(address project);
    event pasueProjectFunctionInteract(address project, bytes4 funcSig);
    event BatchSetInfo(address module_address);
    event RemovePartialInfo(address module_address);

    /**
     * @dev 为项目注册一个受保护函数。
     * @param project 项目地址。
     * @param manager 管理者地址。
     * @param funcSig 函数选择器。
     * @param params 参数列表。
     * @param enableModules 启用的模块列表。
     */
    // TODO:这个地方现在有点问题：我感觉注册不应该注册的是函数，而应该是项目
    function register(
        address project,
        address manager,
        bytes4 funcSig,
        string[] memory params,
        address[] memory enableModules
    ) external {
        protectFuncRegistry[project][funcSig] = ProtectInfo(
            params,
            enableModules,
            false
        );
        projectManagers[project] = manager;
        protectFuncSet[project].push(funcSig);
        pauseMap[project] = false;
        emit RegisterInfo(project, funcSig, manager, params, enableModules);
    }

    /**
     * @dev 为单个项目注册多个函数信息
     * @param project 项目地址。
     * @param manager 管理者地址。
     * @param funcSig 函数选择器。
     * @param params 参数列表。
     * @param enableModules 启用的模块列表。
     */
    // TODO:完善批量注册
    function batchRegister(
        address project,
        address manager,
        bytes4[] calldata funcSig,
        string[][] memory params,
        address[] memory enableModules
    ) external {}

    // =============================查询=============================
    /**
     * @dev 获取受保护函数的信息。
     * @param project 项目地址。
     * @param funcSig 函数选择器。
     * @return 受保护函数的信息。
     */
    function getProtectInfo(
        address project,
        bytes4 funcSig
    ) external view returns (ProtectInfo memory) {
        return protectFuncRegistry[project][funcSig];
    }

    /**
     * @dev 获取检测模块的地址。
     * @param project 项目地址。
     * @param funcSig 函数选择器。
     * @return 项目使用的检测模块的地址列表。
     */
    function getDetectModAddress(
        address project,
        bytes4 funcSig
    ) external view returns (address[] memory) {
        return protectFuncRegistry[project][funcSig].enableModules;
    }

    /**
     * @dev 获取所有模块的信息。
     * @return 所有模块的信息。
     */
    function getAllModule() external view returns (ModuleInfo[] memory) {
        return moduleInfos;
    }

    //=====================================模块相关函数=============================================

    /**
     * @dev 更新模块的信息。
     * @param module_address 模块地址。
     * @param data 模块信息。
     */
    // TODO:考虑增加权限访问，只有owner、manager可以调用module中的函数
    function updataModuleInfo(
        address module_address,
        bytes memory data
    ) external {
        // 设置模块信息
        IModule(module_address).setInfo(data);
        // 释放事件
        emit UpdateModuleInfo(moduleNames[module_address]);
    }

    /**
     * @dev 删除项目在模块中的信息。
     * @param module_address 模块地址。
     * @param data 模块信息。
     */
    function removeModuleInfo(
        address module_address,
        bytes memory data
    ) external {
        // 设置模块信息，只有owner、router、模块管理员可以调用
        IModule(module_address).removeInfo(data);
        // 释放事件
        emit RemoveModuleInfo(moduleNames[module_address]);
    }

    /**
     * @dev 添加模块。
     * @param modAddreess 模块地址。
     * @param modAdmin 模块管理员地址。
     * @param description 描述。
     * @param enable 启用状态。
     */
    function addModule(
        address modAddreess,
        address modAdmin,
        string memory description,
        bool enable
    ) external {
        // 添加模块
        moduleInfos.push(
            ModuleInfo(address(modAddreess), modAdmin, description, enable)
        );
        moduleNames[modAddreess] = description;
        moduleIndex[modAddreess] = uint64(moduleInfos.length);
        // 释放事件
        emit AddModule(address(modAddreess), modAdmin, description, enable);
    }

    /**
     * @dev 删除模块。
     * @param modAddreess 模块地址。
     */
    function removeModule(address modAddreess) external onlyOwner {
        uint64 module_index = moduleIndex[modAddreess];
        // 将待删除模块与最后一个模块交换
        if (module_index < moduleInfos.length - 1) {
            // 交换index
            moduleIndex[
                moduleInfos[moduleInfos.length - 1].modAddress
            ] = module_index;
            moduleIndex[modAddreess] = 0;
            moduleInfos[module_index] = moduleInfos[moduleInfos.length - 1];
        }
        // 删除最后一个模块
        moduleInfos.pop();
        // 释放事件
        emit RemoveModule(moduleNames[modAddreess], modAddreess);
        // 删除其他内容
        moduleNames[modAddreess] = "";
    }

    /**
     * @dev 暂停指定项目的指定函数
     * @param project 项目地址
     * @param funcSig 函数签名
     */
    function pauseFunction(address project, bytes4 funcSig) external {
        require(
            msg.sender == projectManagers[project] || msg.sender == owner,
            "Registry--pauseFunction:permission denied"
        );
        protectFuncRegistry[project][funcSig].is_pause = true;
        // 释放事件
        emit pasueProjectFunctionInteract(project, funcSig);
    }

    function unpauseFunction(address project, bytes4 funcSig) external {
        require(
            msg.sender == projectManagers[project] || msg.sender == owner,
            "Registry--unpauseFunction:permission denied"
        );
        protectFuncRegistry[project][funcSig].is_pause = false;
        // 释放事件
        emit pasueProjectFunctionInteract(project, funcSig);
    }

    /**
     * @dev 暂停指定项目的所有函数
     * @param project 项目地址
     */
    function pauseProject(address project) external {
        require(
            msg.sender == projectManagers[project] || msg.sender == owner,
            "Registry--pauseProject:permission denied"
        );
        pauseMap[project] = true;
        // 释放事件
        emit pauseProjectInteract(project);
    }

    function unpauseProject(address project) external {
        // require(
        //     msg.sender == projectManagers[project] || msg.sender == owner, "Registry--unpauseProject:permission denied"
        // );
        pauseMap[project] = false;
        // 释放事件
        emit pauseProjectInteract(project);
    }

    // 这些取消暂停的函数应该被修饰？
    /**
     * @dev 暂停模块。
     * @param module_address 模块地址。
     */
    function pauseModule(address module_address) external {
        uint64 module_index = moduleIndex[module_address];
        moduleInfos[module_index].enable = false;
        // 释放事件
        emit PauseModule(module_address);
    }

    /**
     * @dev 恢复模块。
     * @param module_address 模块地址。
     */
    function unpauseModule(address module_address) external {
        uint64 module_index = moduleIndex[module_address];
        moduleInfos[module_index].enable = true;
        // 释放事件
        emit UnpauseModule(module_address);
    }

    /**
     * @dev 暂停所有模块。
     */
    function pauseAllModule() external onlyOwner {
        for (uint64 i = 0; i < moduleInfos.length; i++) {
            moduleInfos[i].enable = false;
        }
        // 释放事件
        emit PauseDetect();
    }

    /**
     * @dev 恢复所有模块。
     */
    function unpauseAllModule() external onlyOwner {
        for (uint64 i = 0; i < moduleInfos.length; i++) {
            moduleInfos[i].enable = true;
        }
        // 释放事件
        emit PauseDetect();
    }

    /**
     * @dev 从项目中删除模块。
     * @param project 项目地址。
     * @param funcSig 函数选择器。
     * @param remove_module_address 待删除的模块地址。
     */
    function removeModuleForProject(
        address project,
        bytes4 funcSig,
        address remove_module_address
    ) external {
        // 读取受保护的函数信息
        address[] memory project_enableModules = protectFuncRegistry[project][
            funcSig
        ].enableModules;
        // 遍历信息，将对应的模块删除
        for (uint256 i = 0; i < project_enableModules.length; i++) {
            address now_module = project_enableModules[i];
            if (now_module == remove_module_address) {
                // 将待删除模块与最后一个模块交换
                protectFuncRegistry[project][funcSig].enableModules[
                        i
                    ] = project_enableModules[project_enableModules.length - 1];
                // 删除最后一个模块
                protectFuncRegistry[project][funcSig].enableModules.pop();
                // 释放事件
                emit RemoveModuleForProject(
                    project,
                    funcSig,
                    moduleNames[now_module],
                    now_module
                );
                return;
            }
        }
        revert("Unable to delete module based on incorrect information");
    }

    // =============================管理函数=============================
    function setOwner(address new_owner) external onlyOwner {
        owner = new_owner;
    }

    function setProjectManager(
        address project,
        address manager
    ) external onlyOwner {
        projectManagers[project] = manager;
    }

    // =============================Initialize==================================

    ///@notice Initialize registry's data.
    ///@param _owner The address of owner
    function initialize(address _owner) external {
        owner = _owner;
    }

    // =============================Authentication==================================
    function batchSetInfo(address module_address, bytes memory data) external {
        IAuthenicationModule(module_address).batchSetInfo(data);
        emit BatchSetInfo(module_address);
    }

    // =============================ParamCheckModule==================================
    function removePartialInfo(
        address module_address,
        bytes memory data
    ) external {
        IParamCheckModule(module_address).removePartialInfo(data);
        emit RemovePartialInfo(module_address);
    }
}
