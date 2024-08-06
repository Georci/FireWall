//SPDX-License-Identifier: MIT
import "../OnchainOracle/Interface/IUniswapV2Pair.sol";
import "../OnchainOracle/Interface/IUniswapV2ERC20.sol";
import "../OnchainOracle/Interface/IERC20.sol";
import "../OnchainOracle/libraries/FixidityLib.sol";
import "../Interface/IPriceCleaningContract.sol";
import {Test, console} from "forge-std/Test.sol";

pragma solidity ^0.8.0;

contract PriceManipulationPrevention {
    using FixidityLib for *;

    uint8 public constant DECIMALS = 24;

    address owner;

    modifier OnlyOwner() {
        require(msg.sender == owner);
        _;
    }

    int256 deviationThreshold;

    // 结算价格信息
    struct DexInfo {
        string dexName;
        string poolDescription;
        address pool;
        address token;
        int256 price;
        int256 deviationThreshold;
    }
    // 项目地址 => 项目中的函数 => 结算价格信息
    mapping(address => mapping(bytes4 => DexInfo)) funcToDexInfo;

    /**
     * @notice 获取受保护项目特定函数进行金融结算所使用的价格信息
     * @param data project 受保护项目
     * @param data func_selector 进行金融结算的函数
     * @param data _dexName 结算所在的交易所
     * @param data _poolDescription 使用币对的描述
     * @param data _pool 使用的币对地址
     * @param data _token 进行金融结算的代币
     * @param data _price当前进行金融结算的代币价格
     * @param data _deviationThreshold项目方允许金融结算时代币价格与真实价格的最大差值
     * @param data _deviationThresholdDecimals项目方设置的代币价格的精度
     * TODO:根据dexName判断当前的pool、token信息是否正确
     */
    function setInfo(bytes memory data) external {
        (
            address project,
            bytes4 func_selector,
            string memory _dexName,
            string memory _poolDescription,
            address _pool,
            address _token,
            int256 _price,
            int256 _deviationThreshold,
            uint8 _deviationThresholdDecimals
        ) = abi.decode(
                data,
                (
                    address,
                    bytes4,
                    string,
                    string,
                    address,
                    address,
                    int256,
                    int256,
                    uint8
                )
            );

        funcToDexInfo[project][func_selector].dexName = _dexName;
        funcToDexInfo[project][func_selector]
            .poolDescription = _poolDescription;
        funcToDexInfo[project][func_selector].pool = _pool;
        funcToDexInfo[project][func_selector].token = _token;

        // 获取对应交易所代币价格
        if (_price == 0) {
            _price = setPriceFromDex(_pool, _token);
        }
        funcToDexInfo[project][func_selector].price = _price;
        if (_deviationThreshold == 0) {
            _deviationThreshold = deviationThreshold;
        }
        if (_deviationThresholdDecimals != DECIMALS) {
            _deviationThreshold = FixidityLib.convertFixed(
                _deviationThreshold,
                _deviationThresholdDecimals,
                DECIMALS
            );
        }
        funcToDexInfo[project][func_selector]
            .deviationThreshold = _deviationThreshold;
    }

    /**
     * @notice 当前我们对任意交易所中的价格都采用瞬时价格以及x * y = k的方式来计算
     * @param pool 当前的代币对地址
     * @param token 需要获取价格的代币
     * @return price 指定代币的价格，以另一代币单位计
     * todo!:Optimize the interface format, not all exchanges are the same as IUniswapV2Pair
     */
    function setPriceFromDex(
        address pool,
        address token
    ) public returns (int256 price) {
        address token0 = IUniswapV2Pair(pool).token0();
        address token1 = IUniswapV2Pair(pool).token1();

        uint token0_balance = IERC20(token0).balanceOf(pool);
        uint token1_balance = IERC20(token1).balanceOf(pool);

        uint8 token0_decimals = IERC20(token0).decimals();
        uint8 token1_decimals = IERC20(token1).decimals();

        console.log("token0_decimals", token0_decimals);
        console.log("token1_decimals", token1_decimals);

        // Ken: Because the decimals of each ERC20 token are different, they need to be standardized.
        // 标准化代币数量到24个小数位
        int256 normalized_token0_balance = FixidityLib.convertFixed(
            int256(token0_balance),
            token0_decimals,
            24
        );
        int256 normalized_token1_balance = FixidityLib.convertFixed(
            int256(token1_balance),
            token1_decimals,
            24
        );

        // 确保价格计算的正确性
        if (token == token0) {
            price = FixidityLib.divide(
                normalized_token1_balance,
                normalized_token0_balance
            );
        } else if (token == token1) {
            price = FixidityLib.divide(
                normalized_token0_balance,
                normalized_token1_balance
            );
        } else {
            revert("Requested token is not part of the pair");
        }
        return price;
    }

    /**
     * @notice 更新偏差阈值
     * @param _deviationThreshold 智能合约防火墙真实价格与结算价格默认的最大偏差(当项目方没有设置时生效)
     */
    function setDeviationThreshold(
        int256 _deviationThreshold
    ) external OnlyOwner {
        deviationThreshold = _deviationThreshold;
    }

    function decimals() external view returns (uint8) {
        return DECIMALS;
    }

    // getRealPrice, compare
    /**
     * @notice 判断当前代币进行金融结算的价格是否是正确价格
     * @param project 进行金融结算的项目名称
     * @param func 进行金融结算的函数选择器
     * @param priceCleanContract 价格清洗合约的地址
     * @param _oracle 获取链下代币价格使用的预言机合约地址
     * @param _needReciprocal 是否是预言机合约地址中的另一种代币
     */
    function compare(
        address project,
        bytes4 func,
        address priceCleanContract,
        address _oracle,
        bool _needReciprocal
    ) external returns (bool) {
        DexInfo memory dexInfo = funcToDexInfo[project][func];
        require(
            dexInfo.deviationThreshold != 0,
            "You need to set deviationThreshold first"
        );

        require(dexInfo.pool != address(0), "error address");
        IPriceCleaningContract(priceCleanContract).setTokenPriceForAllDexs();
        IPriceCleaningContract(priceCleanContract).updateOffchainPrice(
            _oracle,
            _needReciprocal
        );
        IPriceCleaningContract(priceCleanContract).cleanDexPrice(_oracle);
        int256 realPrice = IPriceCleaningContract(priceCleanContract)
            .calculateRealPrice(dexInfo.token);

        console.log("realPrice is:", uint256(realPrice));

        int256 priceDifference = dexInfo.price > realPrice
            ? dexInfo.price - realPrice
            : realPrice - dexInfo.price;

        if (priceDifference > dexInfo.deviationThreshold) {
            return false;
        }
        return true;
    }

    function changeOwner(address newOwner) external OnlyOwner {
        owner = newOwner;
    }

    // initialize logic contract
    function initialize(address _owner) external {
        owner = _owner;
    }
}
