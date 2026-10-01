// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Challenge token. 18 decimals; the constructor mints the whole supply to the
///         deployer.
contract DamnValuableToken is ERC20 {
    constructor() ERC20("DamnValuableToken", "DVT") {
        _mint(msg.sender, 1_000_000_000e18);
    }
}
