pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import "../src/Implemention/PriceManipulationModule/PriceManipulationPreventionModule.sol";
import "../src/Implemention/OnchainOracle/libraries/FixedPoint.sol";
import "../src/Implemention/OnchainOracle/libraries/FixidityLib.sol";
import "../src/Implemention/OnchainOracle/PriceCleaningContract.sol";

// import {CheatCodes} from "../src/Implemention/Interface/interface.sol";

contract UnitTest is Test {
    using FixedPoint for *;
    PriceManipulationPrevention module;
    PriceCleaningContract cleaningContract;

    address doge_usdt = 0xfCd13EA0B906f2f87229650b8D93A51B2e839EBD;
    address doge = 0x4206931337dc273a630d328dA6441786BfaD668f;
    address usdt = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address wbtc_eth = 0xCBCdF9626bC03E24f779434178A73a0B4bad62eD;
    address wbtc = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address eth_usdt = 0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852;

    address owner = vm.addr(1);

    // function setUp() public {
    //     vm.createSelectFork("mainnet", 20411921);
    //     module = new PriceManipulationPrevention();
    //     vm.prank(owner);
    //     cleaningContract = new PriceCleaningContract(usdt, 5, 3);
    // }

    // function testPriceCleaning() public {
    //     vm.startPrank(owner);
    //     cleaningContract.addDexInfo(
    //         "UniswapV2",
    //         "ETH / USDT",
    //         eth_usdt,
    //         usdt,
    //         0,
    //         1
    //     );
    //     cleaningContract.setTokenPriceForOneDex(0);

    //     address OffchainOrcale_eth_usdt = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    //     cleaningContract.updateOffchainPrice(OffchainOrcale_eth_usdt, true);
    //     cleaningContract.cleanDexPrice();
    //     cleaningContract.getDexInfo(0);
    //     cleaningContract.calculateRealPrice();
    // }

    function testFixidityLib() public {
        int256 a = FixidityLib.convertFixed(20461982934249072753353, 18, 6);
        emit log_named_int("a is :", a);
    }
}
