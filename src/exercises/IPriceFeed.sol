// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Price oracle interface
/// @notice Deliberately shaped like Chainlink's AggregatorV3, so that swapping in the real
///         feed later is a drop-in change.
/// @dev On real Chainlink feeds decimals() differs from pair to pair (ETH/USD uses 8, but
///      not every pair does). Hardcoding 8 is a simplification this exercise makes to keep
///      the focus on decimal handling.
interface IPriceFeed {
    function decimals() external view returns (uint8);

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}
