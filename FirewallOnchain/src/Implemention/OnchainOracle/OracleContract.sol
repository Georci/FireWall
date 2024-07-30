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
        r.observations = abi.decode(_report, (int192[]));

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
}
