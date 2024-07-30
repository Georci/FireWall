pragma solidity ^0.8.0;

import "./Interface/AggregatorV2V3Interface.sol";
import "./Interface/IUniswapV2Pair.sol";
import "../Interface/IPriceCleaningContract.sol";
import "../OnchainOracle/Interface/IERC20.sol";
import "../OnchainOracle/libraries/FixidityLib.sol";
import "forge-std/Test.sol";
// Q1:价格清洗合约应该是所有代币对共用一个，还是每个代币对对应一个，如果对应一个的话要不要持久化保存出数据
// Q2:txAmount怎么得到，怎样设置？
contract PriceCleaningContract is IPriceCleaningContract{
    using FixidityLib for *;
    // 所有价格(链上、链下)统一使用24位小数
    uint8 public constant DECIMALS = 24;

    // 存储当前价格清洗合约使用的主流交易所(用mapping还是用数组)
    DexInfo[] public dexInfos;

    // 通过deviationThreshold筛选出真实价格计算使用的交易所
    DexInfo[] private usefulDexInfos;

    // latestOffchianPrice from oracle contract
    int256 latestOffchianPrice;
    uint8 offchainPricedecimals;

    // example：0.5%, 5, 3
    int192 deviationThreshold;
    uint8 deviationThresholdDecimals;

    address owner;

    address cleaningToken;
    event UpdateOffchainPrice(address updater, int256 updatePrice);
    event UpdateOffchainPriceAndDecimals(
        address updater,
        int256 updatePrice,
        uint8 updateDecimals
    );
    event AddDexInfo(
        address updater,
        string _dexName,
        string _poolDescription,
        address pool,
        address token
    );
    event UpdateDexInfo(
        address updater,
        string _dexName,
        string _poolDescription,
        address pool,
        address token
    );
    event SetTokenPriceForOneDex(
        address seter,
        string _dexName,
        string _poolDescription,
        address pool,
        address token
    );
    event SetTokenPriceForAllDex(address seter, address token);

    constructor(
        address _token,
        int192 _deviationThreshold,
        uint8 _deviationThresholdDecimals
    ) {
        owner = msg.sender;
        cleaningToken = _token;
        deviationThreshold = _deviationThreshold;
        deviationThresholdDecimals = _deviationThresholdDecimals;
    }

    modifier OnlyOwner() {
        require(msg.sender == owner, "only owner can call this function!");
        _;
    }

    // 目前，我认为PriceCleaning合约中不应该保存历史数据，而且我们只针对五个交易所中同一种代币价格进行清洗
    function addDexInfo(
        string calldata _dexName,
        string calldata _poolDescription,
        address _pool,
        address _token,
        int256 _price,
        uint8 _txAmount
    ) external OnlyOwner {
        require(_token == cleaningToken, "Token is not cleaningToken");
        address token0 = IUniswapV2Pair(_pool).token0();
        address token1 = IUniswapV2Pair(_pool).token1();
        require(
            _token == token0 || _token == token1,
            "This pool doesn't includes cleaningToken"
        );

        for (uint8 i = 0; i < dexInfos.length; i++) {
            require(dexInfos[i].pool != _pool, "This pool already exsit!");
        }

        // 手动增加数组长度并赋值
        dexInfos.push(
            DexInfo({
                dexName: _dexName,
                poolDescription: _poolDescription,
                pool: _pool,
                token: _token,
                price: _price,
                txAmount: _txAmount
            })
        );

        emit AddDexInfo(msg.sender, _dexName, _poolDescription, _pool, _token);
    }

    function updateDexInfo(
        string calldata _dexName,
        string calldata _poolDescription,
        address _pool,
        uint8 index
    ) external OnlyOwner {
        address token = cleaningToken;

        require(index < dexInfos.length, "index exceeds!");
        address token0 = IUniswapV2Pair(_pool).token0();
        address token1 = IUniswapV2Pair(_pool).token1();
        require(
            token == token0 || token == token1,
            "This pool doesn't includes cleaningToken"
        );

        dexInfos[index].dexName = _dexName;
        dexInfos[index].poolDescription = _poolDescription;
        dexInfos[index].pool = _pool;

        emit UpdateDexInfo(
            msg.sender,
            _dexName,
            _poolDescription,
            _pool,
            token
        );
    }

    function setTokenPriceForAllDexs() external OnlyOwner {
        int256 price;
        uint dexslength = dexInfos.length;

        for (uint8 i = 0; i < dexslength; i++) {
            address targetPool = dexInfos[i].pool;
            address targetToken = dexInfos[i].token;

            address token0 = IUniswapV2Pair(targetPool).token0();
            address token1 = IUniswapV2Pair(targetPool).token1();

            uint token0_balance = IERC20(token0).balanceOf(targetPool);
            uint token1_balance = IERC20(token1).balanceOf(targetPool);

            uint8 token0_decimals = IERC20(token0).decimals();
            uint8 token1_decimals = IERC20(token1).decimals();

            // Ken: Because the decimals of each ERC20 token are different, they need to be standardized.
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

            if (targetToken == token0) {
                price = FixidityLib.divide(
                    normalized_token1_balance,
                    normalized_token0_balance
                );
            } else if (targetToken == token1) {
                price = FixidityLib.divide(
                    normalized_token0_balance,
                    normalized_token1_balance
                );
            } else {
                revert("Requested token is not part of the pair");
            }
            dexInfos[i].price = price;
        }
        emit SetTokenPriceForAllDex(tx.origin, cleaningToken);
    }

    /**
     * @notice 获取当前交易所数组中指定位置的交易所信息
     * @param index 查找的交易所信息位于当前数组中的位置
     */
    function getDexInfo(
        uint8 index
    ) external view returns (DexInfo memory dexInfo) {
        require(index < dexInfos.length, "index exceeds limit!");

        dexInfo = dexInfos[index];
        return dexInfo;
    }

    function getUsefulDexInfo(
        uint8 index
    ) external view returns (DexInfo memory dexInfo) {
        require(index < usefulDexInfos.length, "index exceeds limit!");

        dexInfo = usefulDexInfos[index];
        return dexInfo;
    }

    /**
     * @notice 为指定交易所中目标代币获取价格
     * @param index 获取代币价格的交易所在当前数组中的位置
     */
    function setTokenPriceForOneDex(uint8 index) external OnlyOwner {
        address targetPool = dexInfos[index].pool;
        address targetToken = dexInfos[index].token;

        address token0 = IUniswapV2Pair(targetPool).token0();
        address token1 = IUniswapV2Pair(targetPool).token1();

        uint token0_balance = IERC20(token0).balanceOf(targetPool);
        uint token1_balance = IERC20(token1).balanceOf(targetPool);

        uint8 token0_decimals = IERC20(token0).decimals();
        uint8 token1_decimals = IERC20(token1).decimals();

        // Ken: Because the decimals of each ERC20 token are different, they need to be standardized.
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

        console.log(
            "normalized_token0_balance :",
            uint256(normalized_token0_balance)
        );
        console.log(
            "normalized_token1_balance :",
            uint256(normalized_token1_balance)
        );

        // 确保价格计算的正确性
        int256 price;
        if (targetToken == token0) {
            price = FixidityLib.divide(
                normalized_token1_balance,
                normalized_token0_balance
            );
        } else if (targetToken == token1) {
            price = FixidityLib.divide(
                normalized_token0_balance,
                normalized_token1_balance
            );
        } else {
            revert("Requested token is not part of the pair");
        }

        dexInfos[index].price = price;
        emit SetTokenPriceForOneDex(
            tx.origin,
            dexInfos[index].dexName,
            dexInfos[index].poolDescription,
            targetPool,
            targetToken
        );
    }

    /**
     * @notice 获取链下价格
     * @param _oracle 我们自己的链上预言机合约，暂时使用的chainlink
     */
    function updateOffchainPrice(
        address _oracle,
        bool _needReciprocal
    ) external OnlyOwner {
        (
            ,
            /*uint80 roundID*/ int256 answer /*uint startedAt*/ /*uint timeStamp*/ /*uint80 answeredInRound*/,
            ,
            ,

        ) = AggregatorV3Interface(_oracle).latestRoundData();
        offchainPricedecimals = AggregatorV3Interface(_oracle).decimals();

        require(answer >= 0, "Answer is negative");
        if (offchainPricedecimals != DECIMALS) {
            answer = FixidityLib.convertFixed(
                answer,
                offchainPricedecimals,
                DECIMALS
            );
        }

        if (!_needReciprocal) {
            latestOffchianPrice = answer;
        } else {
            latestOffchianPrice = FixidityLib.reciprocal(answer);
        }
        console.log("latestOffchianPrice is :", uint256(latestOffchianPrice));

        emit UpdateOffchainPrice(msg.sender, latestOffchianPrice);
    }

    /**
     * @notice 清洗交易所中的价格，剔除掉不可信的代币价格
     */
    function cleanDexPrice() external OnlyOwner {
        for (uint8 i = 0; i < dexInfos.length; i++) {
            int256 price;
            price = dexInfos[i].price;
            bool isUseful = compareOffchainpriceWithFixedPrice(price);
            console.log("isUseful :", isUseful);

            if (isUseful) usefulDexInfos.push(dexInfos[i]);
        }
    }

    /**
     * @notice 比较传入的链上价格与当前合约保存的链下价格，若二者差距大于deviationThreshold，则return false
     * @param onchainPrice 链上价格，使用int256(int64.int192)的形式保存
     */
    function compareOffchainpriceWithFixedPrice(
        int256 onchainPrice
    ) internal returns (bool) {
        int256 offchainPrice = latestOffchianPrice;
        require(offchainPrice != 0, "You need to upload offchian price first");

        console.log("offchainPrice is :", uint256(offchainPrice));
        console.log("onchainPrice is :", uint256(onchainPrice));
        // 链上价格与链下价格在decimals被修正到一样的时候，可以直接使用加减进行比较了
        int256 priceDifference = onchainPrice > offchainPrice
            ? onchainPrice - offchainPrice
            : offchainPrice - onchainPrice;

        console.log("priceDifference :", uint256(priceDifference));

        // 比较
        require(deviationThreshold != 0, "You need to set deviationThreshold first");
        int256 deviationThresholdFixed = FixidityLib.convertFixed(
            deviationThreshold,
            deviationThresholdDecimals,
            DECIMALS
        );
        if (priceDifference > deviationThresholdFixed) {
            return false;
        }
        return true;
    }

    // TODO:具体来说要需要获取几个交易所在当前以太坊浏览器中的交易占比
    // 利用个交易所的交易占比乘以其交易所提供的价格计算真实价格
    function calculateRealPrice()
        external
        OnlyOwner
        returns (int256 realPrice)
    {
        uint16 txTotal = 0;
        int256 weightedPriceSum = 0;

        for (uint8 i = 0; i < usefulDexInfos.length; i++) {
            txTotal += usefulDexInfos[i].txAmount;
            weightedPriceSum +=
                usefulDexInfos[i].price *
                int8(usefulDexInfos[i].txAmount);
        }

        console.log("txTotal is:", txTotal);
        console.log("weightedPriceSum is:", uint256(weightedPriceSum));
        if (txTotal > 0) {
            realPrice = FixidityLib.divide(
                weightedPriceSum,
                int256(int16(txTotal))
            );
        } else {
            realPrice = 0; // 或者可以设定一个默认价格或抛出错误
        }
        // realPrice默认具有48位小数
        return realPrice;
    }

    function changeOwner(address newOwner) external OnlyOwner {
        owner = newOwner;
    }

    /**
     * @notice 设置交易所中价格与链下价格允许偏差的阈值以及阈值的小数位数
     * @param newDeviationThreshold 交易所中价格与链下价格允许偏差的阈值
     * @param newDeviationThresholdDecimals 链下价格小数位数
     */
    function setDeviationThreshold(
        int192 newDeviationThreshold,
        uint8 newDeviationThresholdDecimals
    ) external OnlyOwner {
        deviationThreshold = newDeviationThreshold;
        deviationThresholdDecimals = newDeviationThresholdDecimals;
    }
}