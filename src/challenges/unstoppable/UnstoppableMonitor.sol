// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";

import {UnstoppableVault} from "./UnstoppableVault.sol";

/// @notice An on-chain monitor: it periodically checks whether the vault's flash-loan
///         function is still alive. On the first sign of trouble it pauses the vault and
///         hands ownership back to the deployer to be repaired.
contract UnstoppableMonitor is Ownable, IERC3156FlashBorrower {
    UnstoppableVault private immutable vault;

    error UnexpectedFlashLoan();

    event FlashLoanStatus(bool success);

    constructor(address _vault) Ownable(msg.sender) {
        vault = UnstoppableVault(_vault);
    }

    function onFlashLoan(address initiator, address token, uint256 amount, uint256 fee, bytes calldata)
        external
        returns (bytes32)
    {
        if (initiator != address(this) || msg.sender != address(vault) || token != address(vault.asset()) || fee != 0) {
            revert UnexpectedFlashLoan();
        }
        IERC20(token).approve(address(vault), amount);
        return keccak256("IERC3156FlashBorrower.onFlashLoan");
    }

    function checkFlashLoan(uint256 amount) external onlyOwner {
        require(amount > 0);

        address asset = address(vault.asset());

        try vault.flashLoan(this, asset, amount, bytes("")) {
            emit FlashLoanStatus(true);
        } catch {
            // Something broke: pause the vault and hand ownership back for a human to look at
            emit FlashLoanStatus(false);
            vault.setPause(true);
            vault.transferOwnership(owner());
        }
    }
}
