// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Test collateral — deliberately 18 decimals
/// @notice A deliberate contrast with MockUSDC (6 decimals): here 1e18 is what one coin
///         means. Keeping those two scales apart is the heart of this exercise.
contract MockWETH is ERC20 {
    error ZeroAmount();

    constructor() ERC20("Mock WETH", "mWETH") {}

    function faucet(address to, uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        _mint(to, amount);
    }
}
