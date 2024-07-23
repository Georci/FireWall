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
    }
    mapping(uint32 /* aggregator round ID */ => Transmission)
        internal s_transmissions;

    /*
     * Versioning
     */
    function typeAndVersion() external pure virtual returns (string memory) {
        return "OffchainAggregator 4.0.0";
    }

    function latestAnswer() external view returns (int256) {}

    function latestTimestamp() external view returns (uint256) {}

    function latestRound() external view returns (uint256) {}

    function getAnswer(uint256 roundId) external view returns (int256) {}

    function getTimestamp(uint256 roundId) external view returns (uint256) {}

    function decimals() external view returns (uint8) {}

    function description() external view returns (string memory) {}

    function version() external view returns (uint256) {}

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
    {}

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
    {}
}
