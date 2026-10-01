// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPriceFeed} from "./IPriceFeed.sol";

/// @title A price oracle you can move by hand
/// @notice Local testing only. Prices carry 8 decimals: 2000e8 means one unit of
///         collateral = $2000.
contract MockPriceFeed is IPriceFeed {
    int256 public answer;

    event PriceSet(int256 answer);

    constructor(int256 initialAnswer) {
        answer = initialAnswer;
    }

    function setPrice(int256 newAnswer) external {
        answer = newAnswer;
        emit PriceSet(newAnswer);
    }

    function decimals() external pure returns (uint8) {
        return 8;
    }

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer_,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (1, answer, block.timestamp, block.timestamp, 1);
    }
}
