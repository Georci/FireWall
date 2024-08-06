// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "./Interface/AggregatorV2V3Interface.sol";
import "./utils/Owned.sol";

/**
 * @notice Onchain verification of reports from the offchain reporting protocol
 * @notice 验证链上来自链下报告协议的报告
 * @dev For details on its operation, see the offchain reporting protocol design
 * @dev doc, which refers to this contract as simply the "contract".
 */
contract OffchainAggregator is Owned, AggregatorV2V3Interface {
    // Transmission records the median answer from the transmit transaction at
    // time timestamp
    struct Transmission {
        int192 answer; // 192 bits ought to be enough for anyone
        uint64 timestamp;
        address transmitter;
    }
    mapping(uint32 /* aggregator round ID */ => Transmission)
        internal s_transmissions;

    struct HotVars {
        uint32 latestAggregatorRoundId;
    }
    HotVars internal s_hotVars;

    // 小数位数
    uint8 public decimals;

    // 比对的描述, 如 ETH / USDT
    string internal s_description;

    // current oracle contract version
    uint256 public constant override version = 4;

    // Lowest answer the system is allowed to report in response to transmissions
    int192 public minAnswer;
    // Highest answer the system is allowed to report in response to transmissions
    int192 public maxAnswer;

    // Ken:The maximum allowed difference between offchain price and dex price
    // example：0.5%, 5, 3
    int192 deviationThresholdOffDex;
    uint8 deviationThresholdOffDexDecimals;

    // 当前代币价格在个交易所中对应的地址
    struct onchainDex {
        string dexName; // 交易所名字
        string description; // 代币对描述
        address pool; // 代币对地址
        bool isHigherValueToken; // 是否是代币数量更少的代币(价值更高的)
        bool isEnable; // 当前交易所是否启用
    }
    onchainDex[] public DexInfos;

    /*
     * Versioning
     */
    function typeAndVersion() external pure virtual returns (string memory) {
        return "OffchainAggregator 4.0.0";
    }

    function latestAnswer() external view returns (int256) {
        return s_transmissions[s_hotVars.latestAggregatorRoundId].answer;
    }

    function latestTimestamp() external view returns (uint256) {
        return s_transmissions[s_hotVars.latestAggregatorRoundId].timestamp;
    }

    function latestRound() external view returns (uint256) {
        return s_hotVars.latestAggregatorRoundId;
    }

    function getAnswer(uint256 _roundId) external view returns (int256) {
        if (_roundId > 0xFFFFFFFF) {
            return 0;
        }
        return s_transmissions[uint32(_roundId)].answer;
    }

    function getTimestamp(uint256 _roundId) external view returns (uint256) {
        if (_roundId > 0xFFFFFFFF) {
            return 0;
        }
        return s_transmissions[uint32(_roundId)].timestamp;
    }

    function getDecimals() external view returns (uint8) {
        return decimals;
    }

    function description() external view returns (string memory) {
        return s_description;
    }

    function getVersion() external view returns (uint256) {
        return version;
    }

    function getDeviationThresholdOffDex() external view returns (int192) {
        return deviationThresholdOffDex;
    }

    function getDeviationThresholdOffDexDecimals()
        external
        view
        returns (uint8)
    {
        return deviationThresholdOffDexDecimals;
    }

    // getRoundData and latestRoundData should both raise "No data present"
    // if they do not have data to report, instead of returning unset values
    // which could be misinterpreted as actual reported values.
    function getRoundData(
        uint80 _roundId
    )
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        require(_roundId <= 0xFFFFFFFF, "roundId exceeds limits");
        Transmission memory transmission = s_transmissions[uint32(_roundId)];
        return (
            _roundId,
            transmission.answer,
            transmission.timestamp,
            transmission.timestamp,
            _roundId
        );
    }

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        roundId = s_hotVars.latestAggregatorRoundId;

        Transmission memory transmission = s_transmissions[uint32(roundId)];
        return (
            roundId,
            transmission.answer,
            transmission.timestamp,
            transmission.timestamp,
            roundId
        );
    }

    /**
     * report new data process
     * todo!: 更新过程验证
     */
    /**
     * @notice indicates that a new report was transmitted
     * @param aggregatorRoundId the round to which this report was assigned
     * @param answer median of the observations attached this report
     * @param transmitter address from which the report was transmitted
     * @param observations observations transmitted with this report
     */
    event NewTransmission(
        uint32 indexed aggregatorRoundId,
        int192 answer,
        address transmitter,
        int192[] observations
    );
    struct ReportData {
        HotVars hotVars;
        int192[] observations;
    }

    // 如果预言机是中心化的，应该不需要加密验证的过程吧
    function transmit(bytes calldata _report) external {
        ReportData memory r;
        r.hotVars = s_hotVars;
        (
            r.observations,
            deviationThresholdOffDex,
            deviationThresholdOffDexDecimals
        ) = abi.decode(_report, ((int192[]), int192, uint8));

        // Check the report contents, and record the result
        for (uint i = 0; i < r.observations.length - 1; i++) {
            bool inOrder = r.observations[i] <= r.observations[i + 1];
            require(inOrder, "observations not sorted");
        }
        int192 median = r.observations[r.observations.length / 2];
        require(
            minAnswer <= median && median <= maxAnswer,
            "median is out of min-max range"
        );
        r.hotVars.latestAggregatorRoundId++;
        s_transmissions[r.hotVars.latestAggregatorRoundId] = Transmission(
            median,
            uint64(block.timestamp),
            tx.origin
        );

        emit NewTransmission(
            r.hotVars.latestAggregatorRoundId,
            median,
            tx.origin,
            r.observations
        );
        // Emit these for backwards compatability with offchain consumers
        // that only support legacy events
        emit NewRound(
            r.hotVars.latestAggregatorRoundId,
            address(0x0), // use zero address since we don't have anybody "starting" the round here
            block.timestamp
        );
        emit AnswerUpdated(
            median,
            r.hotVars.latestAggregatorRoundId,
            block.timestamp
        );

        s_hotVars = r.hotVars;
    }

    /**
     * @notice 对于一个代币对种类，增加该代币对进行价格清洗时使用交易所信息
     * @param _Info 链下构建的交易所信息
     */
    // TODO:缺少权限控制
    function addOnchainDex(bytes calldata _Info) external {
        onchainDex memory r;
        r = abi.decode(_Info, (onchainDex));

        for (uint8 i = 0; i < DexInfos.length; i++) {
            require(r.pool != DexInfos[i].pool, "this pool has already exsit!");
        }

        DexInfos.push(r);
    }

    /**
     * @notice 查看当前代币对进行价格清洗可使用的交易所信息
     * @param index 数组索引
     */
    function getOnchainDex(
        uint8 index
    ) external view returns (onchainDex memory data) {
        data = DexInfos[index];
        return data;
    }

    /**
     * @notice 对于一个代币对种类，删除该代币对进行价格清洗时使用交易所信息
     * @param index 所移除的元素在数组中的索引
     */
    // TODO:缺少权限控制
    function removeOnchainDex(uint8 index) external {
        require(index < DexInfos.length, "Index out of bounds");

        // 将要删除的元素与最后一个元素交换
        DexInfos[index] = DexInfos[DexInfos.length - 1];
        // 删除最后一个元素
        DexInfos.pop();
    }

    /**
     * @notice 更新交易所的池地址
     * @param index 所要更新的交易所所在的索引
     * @param newPool 新的池地址
     */
    function updatePool(uint8 index, address newPool) external {
        require(index < DexInfos.length, "Index out of bounds");
        DexInfos[index].pool = newPool;
    }

    /**
     * @notice 更新交易所是否是价值更高的代币
     * @param index 所要更新的交易所所在的索引
     * @param isHigherValueToken 新的值
     */
    function updateIsHigherValueToken(
        uint8 index,
        bool isHigherValueToken
    ) external {
        require(index < DexInfos.length, "Index out of bounds");
        DexInfos[index].isHigherValueToken = isHigherValueToken;
    }

    /**
     * @notice 更新交易所是否启用
     * @param index 所要更新的交易所所在的索引
     * @param isEnabled 新的值
     */
    function updateIsEnabled(uint8 index, bool isEnabled) external {
        require(index < DexInfos.length, "Index out of bounds");
        DexInfos[index].isEnable = isEnabled;
    }
}
