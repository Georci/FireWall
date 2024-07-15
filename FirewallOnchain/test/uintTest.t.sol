import {Test, console} from "../lib/forge-std/src/Test.sol";
import {FireWallRouter} from "../src/Implemention/Router.sol";
import {FireWallRegistry} from "../src/Implemention/Registry.sol";
import {IModule} from "../src/Implemention/IModule.sol";
import {AuthModule} from "../src/Implemention/AuthenticationModule.sol";
import {TestContract} from "../src/example/test_contract.sol";
import {ParamCheckModule} from "../src/Implemention/ParamCheckModule.sol";

//============================== proxy =============================
import {ProxyForRegistry} from "../src/proxy/proxyForRegistry.sol";
import {FireWallRegistryV2} from "../src/Implemention/RegistryV2.sol";
import {ProxyForRouter} from "../src/proxy/proxyForRouter.sol";
import {FireWallRouterV2} from "../src/Implemention/RouterV2.sol";
import {SimpleSwap} from "../src/example/testFireWallexp.sol";

import "../src/proxy/utils/StorageSlot.sol";
import "../src/proxy/utils/Address.sol";

contract uintTest is Test {
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
    TestContract testContract;
    // SimpleSwap testContract;

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
        proxyForRegistry.CallOn(addModuledata1);
        // (bool success, ) = address(proxyForRegistry).call(addModuledata1);
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

        //========================deploy and registry test contract=====================
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
        //黑名单拦截1
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

        //黑名单拦截2
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

        //参数拦截
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

    function test1() public {
        vm.prank(black, black);
        testContract.test_attack(101);
    }

    // 对该地址启用的是函数级别的限制
    function testBlackOnAnotherFunc() public {
        vm.prank(black, black);
        testContract.test_Attack(101);
    }

    //TODO:测试一下register，测试一下 3.参数模块连续值和离散值的区别
    function testRemoveBlackList() public {
        bytes memory removeAuthdata = abi.encode(
            address(testContract),
            testContract.test_attack.selector,
            black
        );
        bytes memory removeModuleData = abi.encodeWithSignature(
            "removeModuleInfo(address,bytes)",
            address(authModule),
            removeAuthdata
        );
        // remove black
        vm.prank(auth_manager);
        proxyForRegistry.CallOn(removeModuleData);
        vm.prank(black, black);
        testContract.test_attack(101);
    }

    // TODO:测试了批量上传，但是感觉项目还得一个个注册register，一个个updateModule，挺难用的
    function testBatchUploadBlack() public {
        // vm.prank(black, black);
        // testContract.test_Attack(101);

        address black1 = vm.addr(10);
        address black2 = vm.addr(11);
        bytes memory batchSetData = abi.encode(
            address(testContract),
            0x40,
            0x02,
            black1,
            black2
        );
        bytes memory batchSetInfoData = abi.encodeWithSignature(
            "batchSetInfo(address,bytes)",
            address(authModule),
            batchSetData
        );

        vm.prank(auth_manager);
        proxyForRegistry.CallOn(batchSetInfoData);
        // vm.prank(black1, black1);
        // testContract.test_Attack(101);
        vm.prank(black2, black2);
        testContract.test_Attack(101);
    }


    function testContinusAndDiscreteParam() public{
        // 离散
        // vm.prank(deployer, deployer);
        // testContract.test_attack(100);

        // 范围
        bytes memory data = abi.encode(
            address(testContract),
            testContract.test_attack.selector,
            0,
            35,
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

        vm.prank(deployer, deployer);
        testContract.test_attack(5);
    }
}
