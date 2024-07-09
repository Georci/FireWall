import {Test, console} from "../lib/forge-std/src/Test.sol";
import {FireWallRouter} from "../src/InitFile/Router.sol";
import {FireWallRegistry} from "../src/InitFile/Registry.sol";
import {IModule} from "../src/InitFile/IModule.sol";
import {AuthModule} from "../src/InitFile/AuthenticationModule.sol";
import {TestContract} from "../src/InitFile/test_contract.sol";
import {ParamCheckModule} from "../src/InitFile/ParamCheckModule.sol";

// import {ProxyForRegistry} from "../src/proxy/proxyForRegistry.sol";
// import {ProxyForRouter} from "../src/proxy/proxyForRouter.sol";
// 例子 可检测参数范围
//

contract FireWallRouterTest is Test {
    address deployer = vm.addr(1);
    address auth_manager = vm.addr(2);
    address param_manager = vm.addr(3);
    address projectManager = vm.addr(4);
    address black = vm.addr(5);

    FireWallRegistry registry;
    FireWallRouter router;
    AuthModule authModule;
    TestContract testContract;
    ParamCheckModule paramModule;

    function setUp() public {
        vm.startPrank(deployer, deployer);
        console.log("deployer %s", deployer);
        router = new FireWallRouter();
        registry = router.registry();
        // 部署param模块
        paramModule = new ParamCheckModule(address(router), address(registry));
        registry.addModule(
            address(paramModule),
            param_manager,
            "param detect",
            true
        );
        // 部署黑名单模块
        authModule = new AuthModule(address(router), address(registry));
        registry.addModule(
            address(authModule),
            auth_manager,
            "black detect",
            true
        );
        // 部署测试合约
        testContract = new TestContract(address(router));
        console.log("testContract %s", address(testContract));
        // 注册信息
        string[] memory params = new string[](1);
        params[0] = "uint256";
        address[] memory enableModules = new address[](2);

        enableModules[0] = address(paramModule);
        enableModules[1] = address(authModule);
        registry.register(
            address(testContract),
            deployer,
            testContract.test_attack.selector,
            params,
            enableModules
        );
        emit log_bytes32(registry.register.selector);
        vm.stopPrank();
        bytes memory data = abi.encode(
            testContract.test_attack.selector,
            address(testContract),
            0,
            0,
            100
        );
        vm.prank(deployer);
        registry.updataModuleInfo(address(paramModule), data);
        bytes memory auth_data = abi.encode(
            testContract.test_attack.selector,
            address(testContract),
            black
        );
        vm.prank(deployer);
        registry.updataModuleInfo(address(authModule), auth_data);
    }

    function test1() public {
        testContract.test_attack(1000);
    }

    function test2() public {
        vm.prank(black, black);
        testContract.test_attack(10);
    }

    function test3() public {
        vm.prank(deployer);
        registry.pauseProject(address(testContract));
        vm.prank(deployer);

        registry.unpauseProject(address(testContract));
        testContract.test_attack(10);
    }
}
