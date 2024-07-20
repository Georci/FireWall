<a name="8814759b"></a>
# **1.简介**
智能合约防火墙作为一种有效拦截攻击交易的方式，其链上系统总体上可以分为三个模块，第一个是路由router模块，该模块作为智能合约防火墙在受保护项目中的入口，负责将当前调用受保护项目的交易信息路由到智能合约防火墙中，在防火墙内部判断交易信息的恶意性。第二个模块是注册表registry模块，该模块用于存放受防火墙保护的项目信息，这些项目信息是由项目方负责人注册登记项目信息；第三个模块是防火墙防护模块，每个防护模块实现特定的防火逻辑，目前已经实现的包括黑名单防护模块、可疑参数防护模块，接下来的工作重点便是增加防护模块，如价格操控以及重入防护模块![image.png](https://cdn.nlark.com/yuque/0/2024/png/40980049/1721137870824-3a9206c0-ae0e-44d0-ab14-9995e2613766.png#averageHue=%23eeeef0&clientId=ub5491445-7b00-4&from=paste&height=432&id=u05519123&originHeight=518&originWidth=1241&originalType=binary&ratio=1.2000000476837158&rotation=0&showTitle=false&size=104494&status=done&style=none&taskId=uc61f7ab0-083e-4771-8c40-416ea4bff0a&title=&width=1034.166625572577)<br />图1 防火墙链上无代理框架<br />同时我们使用了可升级模式来实现Router模块和Registry模块，这样做的原因是为了尽可能减小由智能合约防火墙本身问题可能带来的不良后果，我们将Router和Registry模块中的数据和业务逻辑分开存储。<br />![image.png](https://cdn.nlark.com/yuque/0/2024/png/40980049/1721138113786-dccb7d45-6670-4a4a-8224-537eab82fcad.png#averageHue=%23ececee&clientId=ub5491445-7b00-4&from=paste&height=553&id=u3045b34a&originHeight=664&originWidth=1401&originalType=binary&ratio=1.2000000476837158&rotation=0&showTitle=false&size=159527&status=done&style=none&taskId=u6e4dea89-9aae-4008-972c-2a00b8cfb9a&title=&width=1167.49995360772)<br />图2 防火墙链上有代理框架
<a name="feeda568"></a>
# 2. **智能合约防火墙链上代码目录结构**

- **src**
   - **Implemention：核心模块**
      - **Interface**
         - **IModule.sol：防护模块通用接口**
         - **IAuthenicationModule.sol：黑名单防护模块专用接口**
         - **IParamCheckModule.sol：参数防护模块专用接口**
         - **interface.sol：test测试合约使用接口**
      - **AuthenticationModule.sol：黑名单防护模块合约**
      - **AuthenticationModuleV2.sol：黑名单防护模块V2**
      - **ParamCheckModule.sol：参数防护模块合约**
      - **Registry.sol：注册表合约**
      - **RegistryV2.sol：注册表合约V2**
      - **Router.sol：路由合约**
      - **RouterV2.sol：路由合约V2**
   - **proxy：与代理相关的代码实现**
      - **access：实现访问控制代码**
      - **interface：代理部分使用接口**
      - **utils：代理部分使用辅助功能**
      - **ERC1967Proxy.sol：1967代理基础合约**
      - **ERC1967Upgrade.sol：1967合约可升级基础合约**
      - **ProxyAdmin.sol：升级权限管理合约**
      - **proxyForRegistry.sol：注册表合约的代理**
      - **proxyForRouter.sol：路由合约的实现**
   - **example：一些测试合约**
      - **test_contract.sol**
      - **testCoinToken.sol**
      - **testFireWallexp.sol**
- **test：智能合约防火墙链上代码测试**
   - **InteractWithOnChainData.t.sol：使用链上真实攻击案例对防火墙测试代码**
   - **proxy_test.t.sol：对智能合约防火墙代理实现测试代码**
   - **uintTest.t.sol：对智能合约核心模块测试代码**

智能合约防火墙链上代码以及其测试模块目录结构如上所示，在源代码src文件夹中，Implemention文件夹存储着智能合约防火墙核心模块的代码，包括各防护模块(目前是黑名单防护模块以及参数防护模块)、各防护模块对应的接口、注册表合约以及路由合约；proxy文件夹中存储着与代理相关的实现，主要包括ERC1967代理与其可升级的功能实现合约(由文件夹access、interface、utils，文件ERC1967Proxy.sol、ERC1967Upgrade.sol共同实现)、升级权限管理合约以及Registry、Router对应的代理实现合约；example文件夹中存储一些测试合约被用来测试防火墙功能，文件test_contract.sol、testFireWallexp.sol是简单的自定义合约，testCoinToken.sol作为真实的攻击案例合约。在测试代码文件夹test中，存储智能合约防火墙链上测试代码。
<a name="270b8c4e"></a>
# 3. **Router模块**
Router模块作为整个项目的入口，具体来说完成了以下两件事：

1. 接收交易信息，并根据交易信息中的目前地址以及目标函数等信息从registry中获取相应的项目保护信息。
2. 传递当前交易信息以及从Registry中获取的受保护项目信息到各检测模块进行交易检测。
```
///@notice ProtectInfosize is the function getProtectInfo's returndata size.
    ///@notice info is the function getProtectInfo's returndata info.
    ///@notice is_ProjectPaused 表示从registry中查找项目是否暂停.
    ///@param data 用作接受当前交易调用受保护项目的信息
    function executeWithDetect(bytes memory data) external returns (bool) {
        // 通过代理从registry中获取项目受保护信息
        bytes memory Proxy_data = abi.encodeWithSignature(
            "getProtectInfo(address,bytes4)",
            msg.sender,
            bytes4(data)
        );
        registry_Proxy.CallOn(Proxy_data);
        // 获取项目受保护信息
        bytes memory ProtectInfo;
        assembly {
            let ProtectInfosize := returndatasize()
            ProtectInfo := mload(0x40)
            mstore(ProtectInfo, ProtectInfosize)
            returndatacopy(add(ProtectInfo, 0x20), 0, ProtectInfosize)
            mstore(0x40, add(add(ProtectInfo, 0x20), ProtectInfosize))
        }
        console.logBytes(ProtectInfo);
        FireWallRegistry.ProtectInfo memory info = abi.decode(
            ProtectInfo,
            (FireWallRegistry.ProtectInfo)
        );

        // 判断是否暂停(项目暂停，函数暂停)
        bytes memory puaseData = abi.encodeWithSignature(
            "pauseMap(address)",
            msg.sender
        );
        registry_Proxy.CallOn(puaseData);
        bytes memory pauseMapInfo;
        // 解析returndata
        assembly {
            let size := returndatasize()
            pauseMapInfo := mload(0x40)
            mstore(pauseMapInfo, size)
            returndatacopy(add(pauseMapInfo, 0x20), 0, size)
            mstore(0x40, add(add(pauseMapInfo, 0x20), size))
        }
        bool is_ProjectPaused = abi.decode(pauseMapInfo, (bool));
        require(!is_ProjectPaused, "project is pause interaction");
        require(!info.is_pause, "project function is pause interaction");
        
        // 遍历
        // 利用接受到的当前交易信息以及获取到的受保护信息对当前交易是否合法进行判断
        for (uint256 index = 0; index < info.enableModules.length; index++) {
            address detectMod = info.enableModules[index];
            // 拆开参数
            string[] memory args = info.params;
            IModule(detectMod).detect(msg.sender, args, data);
        }
        return true;
    }
```
<a name="ec5ff481"></a>
# 4. **Registry模块**
Registry注册表模块主要用来存储注册的项目信息以及启用的保护模块信息，我们从以上两个方面来分析Registry模块的功能。<br />![image.png](https://cdn.nlark.com/yuque/0/2024/png/40980049/1721047033818-52eddd63-e4c1-4afb-bb8d-e83087959bb5.png#averageHue=%23212020&clientId=u21b6ed43-e49d-4&from=paste&height=232&id=ub7229d5a&originHeight=278&originWidth=416&originalType=binary&ratio=1.8000000715255737&rotation=0&showTitle=false&size=21844&status=done&style=none&taskId=u49f32301-2644-4865-9206-4dec6726883&title=&width=346.66665289137154)

1. 与受保护项目相关功能：

(1) function register()，在该函数中:<br />参数：项目地址、项目经理、项目受保护的函数选择器、函数参数类型该项目启用的模块<br />说明：该函数用于保存项目受保护的信息并释放注册事件
```
/**
     * @dev 为项目注册一个受保护函数。
     * @param project 项目地址。
     * @param manager 管理者地址。
     * @param funcSig 函数选择器。
     * @param params 参数列表。
     * @param enableModules 启用的模块列表。
     */
    function register(
        address project,
        address manager,
        bytes4 funcSig,
        string[] memory params,
        address[] memory enableModules
    ) external {
        // 存储项目受保护信息
        protectFuncRegistry[project][funcSig] = ProtectInfo(params, enableModules, false);
        projectManagers[project] = manager;
        protectFuncSet[project].push(funcSig);
        pauseMap[project] = false;
        // 释放注册事件
        emit RegisterInfo(project, funcSig, manager, params, enableModules);
    }
```
(2) function pauseFunction()，在该函数中：<br />参数：项目地址project、函数选择器funcSig<br />说明：暂停当前受保护项目中的funcSig函数，任何在暂停期间对该函数的调用都将被revert
```
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
```
(3) function unpauseFunction()，在该函数中：<br />参数：项目地址project、函数选择器funcSig<br />说明：解除当前受保护项目中funcSig的暂停调用<br />(4) function pauseProject()，在该函数中：<br />参数：项目地址project<br />说明：暂停当前受保护项目project，任何在暂停期间对该项目中函数的调用都将被revert
```
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
```
(5) function unpauseProject()，在该函数中：<br />参数：项目地址project<br />说明：解除当前受保护项目project的暂停调用<br />(6) function getProtectInfo()，在该函数中：<br />参数：项目地址project、函数选择器funcSig<br />返回值：保护信息<br />说明：获取当前项目对应函数的保护信息

1. 与保护模块相关功能：

(1) function getDetectModAddress()，在该函数中：<br />参数：项目地址、函数选择器<br />返回值：模块地址列表<br />说明：获取当前项目中受保护函数启用的模块地址<br />(2) function getAllModule()，在该函数中：<br />返回值：registry注册表添加的全部模块地址列表<br />说明：获取当前项目中受保护函数启用的模块地址<br />(3) function updataModuleInfo()，在该函数中：<br />参数：更新信息的模块地址module_address、更新信息数据data<br />说明：使用输入的更新信息调用对应模块中的信息更新函数
```
/**
     * @dev 更新模块的信息。
     * @param module_address 模块地址。
     * @param data 模块信息。
     */
    function updataModuleInfo(
        address module_address,
        bytes memory data
    ) external {
        // 设置模块信息
        IModule(module_address).setInfo(data);
        // 释放事件
        emit UpdateModuleInfo(moduleNames[module_address]);
    }
```
(4) function removeModuleInfo()，在该函数中：<br />参数：删除信息的模块地址module_address、删除信息数据data<br />说明：使用输入的删除信息调用对应模块中的信息删除函数<br />(5) function addModule()，在该函数中：<br />参数：增加的模块地址modAddreess、模块管理员modAdmin、该模块的描述description、模块启用状态enable<br />说明：添加防护模块到registry注册表
```
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
```
(6) function removeModule()，在该函数中：<br />参数：移除的模块地址modAddreess<br />说明：移除registry注册表中添加的防护模块<br />(7) function pauseModule()，在该函数中：<br />参数：暂停的模块地址module_address<br />说明：暂停当前防护模块在registry中的使用，防护模块暂停后进行交易检测的时候不使用<br />(8) function unpauseModule()，在该函数中：<br />参数：解除暂停的模块地址module_address<br />说明：解除当前防护模块的暂停<br />(9) function removeModuleForProject()，在该函数中：<br />参数：移除防护模块的项目地址project，该模块所保护的函数funcSig，移除的模块地址remove_module_address<br />说明：移除当前项目中受保护函数funcSig正在使用的remove_module_address模块
```
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
```
<a name="de46c6ec"></a>
# 5. **proxy模块**
在实现代理方面，我们采取这样的方式：EIP1967标准 + 代理中存储升级逻辑，目前在代理方面仍然有一些的可优化的点，例如权限访问控制方面、代码轻量化方面。
<a name="5986e1d0"></a>
### 5.1 调用方式
目前在我们的防火墙系统中所有与router和registry相关的操作全部走代理实现，我们在代理中实现了两种调用方式：<br />![image.png](https://cdn.nlark.com/yuque/0/2024/png/40980049/1721046942453-347608d8-668e-407e-82d0-ae31098c174c.png#averageHue=%232c2a27&clientId=u21b6ed43-e49d-4&from=paste&height=55&id=u8b8a51d7&originHeight=66&originWidth=913&originalType=binary&ratio=1.8000000715255737&rotation=0&showTitle=false&size=16258&status=done&style=none&taskId=ubabd0c12-6184-4bed-8401-5d7ab70f6d8&title=&width=760.8333031005342)<br />1.使用函数CallOn作为入口，调用对应逻辑合约中的函数
```
// 调用防火墙的方法：1.CallOn 2.硬编码
    function CallOn(bytes memory _data) external {
        _fallbackCallOn();
    }
```
```
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
```
2.采取硬编码的方式调用直接call代理合约
```
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
```
<a name="7cb9b24b"></a>
### 5.2 升级函数
(1) function _upgradeTo()，该函数中：<br />参数：新的逻辑合约地址newImplementation<br />说明：升级逻辑合约地址到输入的地址newImplementation并释放升级事件
```
function _upgradeTo(address newImplementation) internal {
        console.log("newImplementation is :", newImplementation);
        _setImplementation(newImplementation);
        emit Upgraded(newImplementation);
    }
```
(2) function _upgradeToAndCall()，该函数中：<br />参数：新的逻辑合约地址newImplementation、调用newImplementation地址中的函数数据data、是否强制调用bool forceCall<br />说明：升级逻辑合约地址到输入的地址newImplementation，并根据data和forceCall的值判断是否需要调用newImplementation中的函数，如果需要则调用
```
function _upgradeToAndCall(
        address newImplementation,
        bytes memory data,
        bool forceCall
    ) internal {
        //KEN：更改逻辑合约地址
        _upgradeTo(newImplementation);

        //KEN：如果data不为空，或者forceCall为真，则调用newImplementation的函数delegatecall，传入data。
        if (data.length > 0 || forceCall) {
            Address.functionDelegateCall(newImplementation, data);
        }
    }
```
<a name="5dce24a6"></a>
# 6. **智能合约防火墙链上系统使用流程**
部署智能合约防火墙链上系统流程如下所示：<br />![a real case_04.png](https://cdn.nlark.com/yuque/0/2024/png/40980049/1721046986099-1c00a638-5bd1-4d5a-9e65-d4814c894241.png#averageHue=%23fefdfd&clientId=u21b6ed43-e49d-4&from=ui&id=ufe6bc3fd&originHeight=1440&originWidth=2560&originalType=binary&ratio=1.8000000715255737&rotation=0&showTitle=false&size=99954&status=done&style=none&taskId=ud676dc7a-7795-409e-813e-7ef8afed6f3&title=)<br />智能合约防火墙部署工作从部署Registry开始：<br />(1) 部署Registry合约<br />(2) 部署proxyRegistry合约，该过程中会使用到registry.address<br />(3) 部署Router合约<br />(4) 部署proxyRouter合约，该过程会使用到router.address<br />(5) 部署防护模块( 该过程需要用到proxyRegistry.address以及proxyRouter.address )<br />(6) 构建好防护模块信息之后，通过代理调用registry合约中的addModule函数添加防护模块<br />(7) 部署受防火墙保护的项目( 这里假设是本地的受保护项目，将其作为testContract )<br />(8) 将testContract的信息传入，通过代理调用registry合约中的register函数注册项目信息<br />具体流程：
```
function setUp() public {
        vm.startPrank(deployer, deployer);
        console.log("deployer %s", deployer);
    
        // ============================= deploy registry and router =============================
        registry = new FireWallRegistry();
        bytes memory InitData_Registry = abi.encodeWithSignature(
            "initialize(address)",
            deployer
        );
        proxyForRegistry = new ProxyForRegistry(
            address(registry),
            admin,
            InitData_Registry
        );
        router = new FireWallRouter();
        bytes memory InitData_Router = abi.encodeWithSignature(
            "initialize(address,address)",
            address(proxyForRegistry),
            deployer
        );
        proxyForRouter = new ProxyForRouter(
            address(router),
            admin,
            InitData_Router
        );

        // ============================= deploy modules through proxy =============================
        // 部署param防护模块
        paramModule = new ParamCheckModule(
            address(proxyForRouter),
            address(proxyForRegistry)
        );
        bytes memory addModuledata1 = abi.encodeWithSignature(
            "addModule(address,address,string,bool)",
            address(paramModule),
            param_manager,
            "param detect",
            true
        );
        proxyForRegistry.CallOn(addModuledata1);
        // (bool success, ) = address(proxyForRegistry).call(addModuledata1);
        // 部署黑名单防护模块
        authModule = new AuthModule(
            address(proxyForRouter),
            address(proxyForRegistry)
        );
        bytes memory addModuledata2 = abi.encodeWithSignature(
            "addModule(address,address,string,bool)",
            address(authModule),
            auth_manager,
            "black detect",
            true
        );
        proxyForRegistry.CallOn(addModuledata2);

        //========================deploy and registry test contract=====================/ 
    	// 部署测试合约以及注册该合约受保护信息
        testContract = new TestContract(address(proxyForRouter));
        // 注册信息
        string[] memory params = new string[](1);
        params[0] = "uint256";
        address[] memory enableModules = new address[](2);
        enableModules[0] = address(paramModule);
        enableModules[1] = address(authModule);
        // 注册
        bytes memory registryData = abi.encodeWithSignature(
            "register(address,address,bytes4,string[],address[])",
            address(testContract),
            deployer,
            testContract.test_attack.selector,
            params,
            enableModules
        );
        proxyForRegistry.CallOn(registryData);

        bytes memory registryData2 = abi.encodeWithSignature(
            "register(address,address,bytes4,string[],address[])",
            address(testContract),
            deployer,
            testContract.test_Attack.selector,
            params,
            enableModules
        );
        proxyForRegistry.CallOn(registryData2);
        vm.stopPrank();
        //添加黑名单拦截1
        bytes memory auth_data = abi.encode(
            address(testContract),
            true,
            testContract.test_attack.selector,
            black,
            true,
            false
        );
        bytes memory authUpdateData = abi.encodeWithSignature(
            "updataModuleInfo(address,bytes)",
            address(authModule),
            auth_data
        );
        vm.prank(deployer);
        proxyForRegistry.CallOn(authUpdateData);

        //添加黑名单拦截2
        bytes memory auth_data2 = abi.encode(
            address(testContract),
            false,
            testContract.test_Attack.selector,
            black,
            false,
            false
        );
        bytes memory authUpdateData2 = abi.encodeWithSignature(
            "updataModuleInfo(address,bytes)",
            address(authModule),
            auth_data2
        );
        vm.prank(deployer);
        proxyForRegistry.CallOn(authUpdateData2);

        //添加参数拦截
        bytes memory data = abi.encode(
            address(testContract),
            testContract.test_attack.selector,
            0,
            100,
            0,
            true
        );
        bytes memory paramUpdataData = abi.encodeWithSignature(
            "updataModuleInfo(address,bytes)",
            address(paramModule),
            data
        );
        vm.prank(deployer);
        proxyForRegistry.CallOn(paramUpdataData);
    }
```
<a name="b39181be"></a>
# 7. **BEVO真实攻击案例**
<a name="9fc767d0"></a>
### 7.1 通缩代币
该真实案例是针对通缩代币项目BEVO的攻击，通缩代币是指链上交易过程中具有通缩机制的加密货币。每当区块链上有一笔与之相关的交易时，都会自动扣除一定比例的代币，即通缩费，而这些通缩费又会分配给现有的持有者，增加流动性。
<a name="4a4343a7"></a>
### 7.2 反射机制
反射机制是实现通缩代币的一种主要方式，在反射机制中，用户每笔交易都会被收取一定的手续费，用于奖励持有代币的用户，但不会触发转账，只是修改一个比例系数。<br />在这个机制中，用户持有的代币数量有两种，分别为tAmount和rAmount。tAmount为用户实际持有的代币数量，rAmount为用户持有该代币的价值量，比例系数rTotal/tTotal，大致的代码实现如下：
```
function balanceOf(address account) public view override returns (uint256) {
        if (_isExcluded[account]) return _tOwned[account];
        return tokenFromReflection(_rOwned[account]);
    }
    
    function tokenFromReflection(uint256 rAmount) public view returns(uint256) {
        require(rAmount <= _rTotal, "Amount must be less than total reflections");
        uint256 currentRate =  _getRate();
        return rAmount.div(currentRate);
    }
    
    function _getRate() private view returns(uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply.div(tSupply);
    }
```
反射机制的token一般都有一个叫deliver的函数，这个函数会销毁调用者的token，降低rTotal的值，所以比例会增加，其他用户反射的token数量也会增加：
```
function deliver(uint256 tAmount) public {
        address sender = _msgSender();
        require(!_isExcluded[sender], "Excluded addresses cannot call this function");
        (uint256 rAmount,,,,,) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rTotal = _rTotal.sub(rAmount);
        _tFeeTotal = _tFeeTotal.add(tAmount);
    }
```
攻击者注意到了该功能，并利用该功能对相应的Uniswap流动性池进行攻击。<br />那么他该如何使用它呢？让我们从 Uniswap 的 skim 功能开始：<br />在Uniswap中，reserve就是储备资金，和token.balanceOf(address(this))有区别。<br />攻击者首先调用 deliver 函数销毁自己的 token，导致 rTotal 的值减小，比例增大，因此反射出来的 token 的值也会增大，token.balanceOf(address(this)) 也会随之增大，导致和储备值出现差距。<br />因此攻击者可以通过调用skim函数转移两个token之间的差额来获利。<br />真实攻击案例，BEVO NFT Art Token（BEVO）：BSC 0xb97502d3976322714c828a890857e776f25c79f187a32e2d548dda1c315d2a7d
