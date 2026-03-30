// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @dev Mimics AggregatorV3Interface. Price is settable to allow simulating price drops in tests.
contract MockPriceFeed {
    int256 private _price;

    constructor(int256 initialPrice) {
        _price = initialPrice;
    }

    function setPrice(int256 newPrice) external {
        _price = newPrice;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (1, _price, block.timestamp, block.timestamp, 1);
    }
}
