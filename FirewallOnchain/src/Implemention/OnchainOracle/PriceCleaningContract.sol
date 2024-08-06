pragma solidity ^0.8.0;

import "./Interface/AggregatorV2V3Interface.sol";
import "./Interface/IUniswapV2Pair.sol";
import "../Interface/IPriceCleaningContract.sol";
import "../OnchainOracle/Interface/IERC20.sol";
import "../OnchainOracle/libraries/FixidityLib.sol";
import "forge-std/Test.sol";

// Q1:价格清洗合约应该是所有代币对共用一个，还是每个代币对对应一个，如果对应一个的话要不要持久化保存出数据
// 目前来看是全部代币对共用一个价格清洗合约，并且我们建立一个合约用来存储所有代币对价格合约的索引
// Q2:txAmount怎么得到，怎样设置？
// 由链下传给链上，同样是以heartbeat和deviation threshold的方式传上来

contract PriceCleaningContract is IPriceCleaningContract {
    using FixidityLib for *;
    // 所有价格(链上、链下)统一使用24位小数
    uint8 public constant DECIMALS = 24;

    // 存储当前价格清洗合约使用的主流交易所(用mapping还是用数组)
    DexInfo[] public dexInfos;
    mapping(address => uint8) tokenTodexInfoIndex;

    // 通过deviationThreshold筛选出真实价格计算使用的交易所
    DexInfo[] private usefulDexInfos;

    // latestOffchianPrice from oracle contract
    int256 latestOffchianPrice;
    uint8 offchainPricedecimals;

    address owner;

    // Ken:目前我认为一个价格清洗合约应该对应一个代币对(当然不是指一个pair因为不同dex同一个币对的pair肯定不同)
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
        address pool
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
    event SetTokenPriceForAllDexs(address seter, address token);

    constructor(address _token) {
        owner = msg.sender;
        cleaningToken = _token;
    }

    modifier OnlyOwner() {
        require(msg.sender == owner, "only owner can call this function!");
        _;
    }

    // 目前，我认为PriceCleaning合约中不应该保存历史数据，而且我们只针对五个交易所中同一对代币价格进行清洗
    /**
     * @notice 添加主流交易所用于计算真实价格
     * @param _dexName 交易所名称
     * @param _poolDescription 币对描述
     * @param _pool 币对地址
     * @param _price 该dex提供的token1代币价格
     * @param _txAmount 该dex当前pool的交易数量(用于计算真实价格)
     */
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
        tokenTodexInfoIndex[cleaningToken] = uint8(dexInfos.length - 1);

        emit AddDexInfo(msg.sender, _dexName, _poolDescription, _pool);
    }

    /**
     * @notice 更新目标交易所信息
     * @param _dexName 交易所名称
     * @param _poolDescription 币对名称
     * @param _pool 币对地址
     * @param index 交易所当前索引
     */
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

    function setTokenPriceForAllDexs() public OnlyOwner {
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
                DECIMALS
            );
            int256 normalized_token1_balance = FixidityLib.convertFixed(
                int256(token1_balance),
                token1_decimals,
                DECIMALS
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
        emit SetTokenPriceForAllDexs(tx.origin, cleaningToken);
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
    function setTokenPriceForOneDex(uint8 index) public OnlyOwner {
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
            DECIMALS
        );
        int256 normalized_token1_balance = FixidityLib.convertFixed(
            int256(token1_balance),
            token1_decimals,
            DECIMALS
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
     * @param _needReciprocal 是否要对当前预言机给的价格取反
     * TODO:这里目前的取反，在我们自己的链下预言机系统实现之后
     */
    function updateOffchainPrice(
        address _oracle,
        bool _needReciprocal
    ) public OnlyOwner {
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
     * @param _oracle 进行价格清洗的链下价格来源合约地址，此处会被用来获取当前链下价格与传入的交易所价格的最大差值
     */
    function cleanDexPrice(address _oracle) public OnlyOwner {
        for (uint8 i = 0; i < dexInfos.length; i++) {
            int256 price;
            price = dexInfos[i].price;
            bool isUseful = compareOffchainpriceWithFixedPrice(price, _oracle);
            console.log("isUseful :", isUseful);

            if (isUseful) usefulDexInfos.push(dexInfos[i]);
        }
    }

    /**
     * @notice 比较传入的链上价格与当前合约保存的链下价格，若二者差距大于deviationThreshold，则return false
     * @param onchainPrice 链上价格，使用int256(int64.int192)的形式保存
     * @param _oracle 进行价格清洗的链下价格来源合约地址，此处会被用来获取当前链下价格与传入的交易所价格的最大差值
     */
    function compareOffchainpriceWithFixedPrice(
        int256 onchainPrice,
        address _oracle
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
        int192 deviationThreshold = AggregatorV2V3Interface(_oracle)
            .getDeviationThresholdOffDex();
        uint8 deviationThresholdDecimals = AggregatorV2V3Interface(_oracle)
            .getDeviationThresholdOffDexDecimals();

        require(
            deviationThreshold != 0,
            "You need to set deviationThreshold first"
        );
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

    // TODO:具体来说要需要获取几个交易所在当前以太坊浏览器中的交易占比，利用个交易所的交易占比乘以其交易所提供的价格计算真实价格
    /**
     * @notice 计算真实价格
     * @param targetToken 进行价格清洗的代币地址
     */
    function calculateRealPrice(
        address targetToken
    ) external OnlyOwner returns (int256 realPrice) {
        require(targetToken == cleaningToken);

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
     * @notice 改变当前合约中目前代币地址
     * @param _cleaningToken 可进行价格清洗代币0地址
     */
    function changeCleaningToken(address _cleaningToken) external OnlyOwner {
        cleaningToken = _cleaningToken;
    }
}
