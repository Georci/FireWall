import {Test, console} from "../lib/forge-std/src/Test.sol";
import {FireWallRouter} from "../src/Implemention/Router.sol";
import {FireWallRegistry} from "../src/Implemention/Registry.sol";
import {IModule} from "../src/Implemention/IModule.sol";
import {AuthModule} from "../src/Implemention/AuthenticationModule.sol";
import {TestContract} from "../src/Implemention/test_contract.sol";
import {ParamCheckModule} from "../src/Implemention/ParamCheckModule.sol";

//============================== proxy =============================
import {ProxyForRegistry} from "../src/proxy/proxyForRegistry.sol";
import {FireWallRegistryV2} from "../src/Implemention/RegistryV2.sol";
import {ProxyForRouter} from "../src/proxy/proxyForRouter.sol";
import {FireWallRouterV2} from "../src/Implemention/RouterV2.sol";
import {SimpleSwap} from "../src/Implemention/testFireWallexp.sol";

import "../src/proxy/utils/StorageSlot.sol";
import "../src/proxy/utils/Address.sol";

// 例子 可检测参数范围

contract FireWallRouterTest is Test {
    address deployer = vm.addr(1);
    address auth_manager = vm.addr(2);
    address param_manager = vm.addr(3);
    address projectManager = vm.addr(4);
    address black = vm.addr(5);
    address admin = vm.addr(6);

    FireWallRegistry registry;
    ProxyForRegistry proxyForRegistry;
    FireWallRouter router;
    ProxyForRouter proxyForRouter;
    AuthModule authModule;
    // TestContract testContract;
    SimpleSwap testContract;

    ParamCheckModule paramModule;

    //升级V2版本
    FireWallRouterV2 RouterV2;
    FireWallRegistryV2 RegistryV2;

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

        // proxyForRouter.CallOn(InitData_Router);
        // bytes memory a = proxyForRegistry.CallOn(InitData_Registry);

        // ============================= deploy modules through proxy =============================
        // 部署param模块
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
        bytes memory removeModuledata1 = abi.encodeWithSignature(
            "removeModule(address)",
            0xd55451d9AEbFAb33dEc7501Bd27A8C6649C11426
        );
        emit log_named_bytes("removeModuledata1 is :", removeModuledata1);
        // proxyForRegistry.CallOn(addModuledata1);
        (bool success, ) = address(proxyForRegistry).call(addModuledata1);
        // 部署黑名单模块
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

        // 部署测试合约
        testContract = new SimpleSwap(address(proxyForRouter));
        console.log("testContract %s", address(testContract));
        // 注册信息
        string[] memory params = new string[](1);
        params[0] = "uint256";
        address[] memory enableModules = new address[](2);

        enableModules[0] = address(paramModule);
        enableModules[1] = address(authModule);

        //注册
        // registry.register(address(testContract), deployer, testContract.test_attack.selector, params, enableModules);
        // 这个地方出现爆红不知道为什么
        bytes memory registryData = abi.encodeWithSignature(
            "register(address,address,bytes4,string[],address[])",
            address(testContract),
            deployer,
            testContract.test.selector,
            params,
            enableModules
        );
        proxyForRegistry.CallOn(registryData);
        vm.stopPrank();

        //设置拦截信息
        //参数拦截
        bytes memory data = abi.encode(
            testContract.test.selector,
            address(testContract),
            0,
            0,
            100
        );
        vm.prank(deployer);
        bytes memory paramUpdataData = abi.encodeWithSignature(
            "updataModuleInfo(address,bytes)",
            address(paramModule),
            data
        );
        proxyForRegistry.CallOn(paramUpdataData);

        //黑名单拦截
        bytes memory auth_data = abi.encode(
            testContract.test.selector,
            address(testContract),
            black
        );
        bytes memory authUpdateData = abi.encodeWithSignature(
            "updataModuleInfo(address,bytes)",
            address(authModule),
            auth_data
        );
        vm.prank(deployer);
        proxyForRegistry.CallOn(authUpdateData);
    }

    function test1() public {
        testContract.test(20);
    }

    // 只有当black作为origin的时候才会被拦截，作为msg.sender的时候不会
    function test2() public {
        vm.prank(admin, admin);
        testContract.test(101);
    }

    function test3() public {
        vm.prank(deployer);
        // 通过代理暂停项目
        bytes memory dataPauseProject = abi.encodeWithSignature(
            "pauseProject(address)",
            address(testContract)
        );
        proxyForRegistry.CallOn(dataPauseProject);
        vm.prank(deployer);

        // 通过代理重启项目
        bytes memory dataUnPauseProject = abi.encodeWithSignature(
            "unpauseProject(address)",
            address(testContract)
        );
        proxyForRegistry.CallOn(dataUnPauseProject);
        testContract.test(10);
    }

    //============================ test upgrade =================================//
    // routerV1没有检查project是否暂停的模块，当一个项目暂停之后应该无法被调用
    function test_RouterProxyUpgrade() public {
        // 升级之前调用
        vm.prank(deployer, deployer);
        testContract.test(10);
        // 升级
        console.log("start upgrade routerProxy!!!");
        RouterV2 = new FireWallRouterV2();
        bytes memory InitData_Router = abi.encodeWithSignature(
            "initialize(address,address)",
            address(proxyForRegistry),
            deployer
        );
        vm.prank(admin);
        proxyForRouter.upgradeToAndCall(address(RouterV2), InitData_Router);
        console.log("upgrade finished!!!");
        // 暂停
        vm.prank(deployer);
        bytes memory pauseData = abi.encodeWithSignature(
            "pauseProject(address)",
            address(testContract)
        );
        proxyForRegistry.CallOn(pauseData);
        // 调用
        vm.prank(deployer, deployer);
        testContract.test(10);
    }

    // 一个项目由于本身有问题，所以被暂停了，但是没有被升级的合约可以由任意用户取消暂停。
    // 将registry升级为V2版本之后，普通用户将无法再取消暂停。
    function test_RegistryProxyUpgrade() public {
        // 升级RouterV2
        console.log("start upgrade routerProxy!!!");
        RouterV2 = new FireWallRouterV2();
        bytes memory InitData_Router = abi.encodeWithSignature(
            "initialize(address,address)",
            address(proxyForRegistry),
            deployer
        );
        vm.prank(admin);
        proxyForRouter.upgradeToAndCall(address(RouterV2), InitData_Router);
        console.log("upgrade finished!!!");
        // 暂停
        vm.prank(deployer);
        bytes memory pauseData = abi.encodeWithSignature(
            "pauseProject(address)",
            address(testContract)
        );
        proxyForRegistry.CallOn(pauseData);
        // 调用
        // vm.prank(admin);
        // testContract.test_attack(10);

        vm.prank(black);
        bytes memory unpauseData = abi.encodeWithSignature(
            "unpauseProject(address)",
            address(testContract)
        );
        proxyForRegistry.CallOn(unpauseData);
        testContract.test(10);

        //升级
        console.log("start upgrade!!!");
        RegistryV2 = new FireWallRegistryV2();
        bytes memory InitData_Registry = abi.encodeWithSignature(
            "initialize(address)",
            deployer
        );
        vm.prank(admin);
        proxyForRegistry.upgradeToAndCall(
            address(RegistryV2),
            InitData_Registry
        );
        console.log("upgrade finished!!!");
        // 升级之后再次暂停
        vm.prank(deployer);
        bytes memory pauseData2 = abi.encodeWithSignature(
            "pauseProject(address)",
            address(testContract)
        );
        proxyForRegistry.CallOn(pauseData2);
        // 普通用户无法再解锁
        vm.prank(black);
        bytes memory unpauseData2 = abi.encodeWithSignature(
            "unpauseProject(address)",
            address(testContract)
        );
        proxyForRegistry.CallOn(unpauseData2);
        testContract.test(10);
    }
}
