//SPDX-License-Identifier:MIT
pragma solidity ^0.8.18;
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title OracleLib
 * @author Amarnath
 * @notice This library is used to check oracle for stale data.
 * If a price is stale, the function will revert and render the DSCEngine unusable
 * DSCEngine shouldbe freezed if prices becomes stale.
 */

library OracleLib {
    error OracleLib__StaleData();

    uint256 private constant TIMEOUT = 3 hours;

    function staleCheckLatestRoundData(
        AggregatorV3Interface priceFeed
    ) public view returns (uint80, int256, uint256, uint256, uint80) {
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();

        uint256 timeElapsed = block.timestamp - updatedAt;
        if (timeElapsed > TIMEOUT) revert OracleLib__StaleData();

        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}
