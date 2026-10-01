// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC3156FlashBorrower, IERC3156FlashLender} from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";

/// @title Unstoppable Vault
/// @notice Ported from the "Unstoppable" challenge in Damn Vulnerable DeFi v4
///         (https://github.com/theredguild/damn-vulnerable-defi).
///         The original builds on solmate/solady; this rewrite uses OpenZeppelin v5 and
///         adds no new dependencies.
///
/// @dev An ERC-4626 vault that hands out free flash loans during a grace period.
///      An accounting flaw is buried in it — see totalAssets() and flashLoan().
contract UnstoppableVault is ERC4626, Ownable, Pausable, ReentrancyGuard, IERC3156FlashLender {
    uint256 public constant FEE_FACTOR = 0.05 ether;
    uint64 public constant GRACE_PERIOD = 30 days;
    uint64 public immutable end = uint64(block.timestamp) + GRACE_PERIOD;

    address public feeRecipient;

    error InvalidAmount(uint256 amount);
    error InvalidBalance();
    error CallbackFailed();
    error UnsupportedCurrency();

    event FeeRecipientUpdated(address indexed newFeeRecipient);

    constructor(IERC20 _token, address _owner, address _feeRecipient)
        ERC4626(_token)
        ERC20("Too Damn Valuable Token", "tDVT")
        Ownable(_owner)
    {
        feeRecipient = _feeRecipient;
        emit FeeRecipientUpdated(_feeRecipient);
    }

    /// @inheritdoc IERC3156FlashLender
    function maxFlashLoan(address _token) public view returns (uint256) {
        if (asset() != _token) {
            return 0;
        }
        return totalAssets();
    }

    /// @inheritdoc IERC3156FlashLender
    function flashFee(address _token, uint256 _amount) public view returns (uint256 fee) {
        if (asset() != _token) {
            revert UnsupportedCurrency();
        }
        if (block.timestamp < end && _amount < maxFlashLoan(_token)) {
            return 0;
        }
        return Math.mulDiv(_amount, FEE_FACTOR, 1e18, Math.Rounding.Ceil);
    }

    /// @dev Note that this defines the total assets as "the contract's own balance".
    ///      Any direct transfer into the vault falsifies that number.
    function totalAssets() public view override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this));
    }

    /// @inheritdoc IERC3156FlashLender
    function flashLoan(IERC3156FlashBorrower receiver, address _token, uint256 amount, bytes calldata data)
        external
        returns (bool)
    {
        if (amount == 0) revert InvalidAmount(0);
        if (asset() != _token) revert UnsupportedCurrency();

        uint256 balanceBefore = totalAssets();

        // The fatal part: "balance" is asserted to equal "total shares" exactly. The
        // moment anyone sends tokens straight into the vault, that equality can never
        // hold again, and the flash loan is bricked for good.
        if (convertToShares(totalSupply()) != balanceBefore) revert InvalidBalance();

        ERC20(_token).transfer(address(receiver), amount);

        uint256 fee = flashFee(_token, amount);
        if (
            receiver.onFlashLoan(msg.sender, asset(), amount, fee, data)
                != keccak256("IERC3156FlashBorrower.onFlashLoan")
        ) {
            revert CallbackFailed();
        }

        ERC20(_token).transferFrom(address(receiver), address(this), amount + fee);
        ERC20(_token).transfer(feeRecipient, fee);

        return true;
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares)
        internal
        override
        whenNotPaused
        nonReentrant
    {
        super._deposit(caller, receiver, assets, shares);
    }

    function _withdraw(address caller, address receiver, address owner_, uint256 assets, uint256 shares)
        internal
        override
        nonReentrant
    {
        super._withdraw(caller, receiver, owner_, assets, shares);
    }

    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        if (_feeRecipient != address(this)) {
            feeRecipient = _feeRecipient;
            emit FeeRecipientUpdated(_feeRecipient);
        }
    }

    function setPause(bool flag) external onlyOwner {
        if (flag) _pause();
        else _unpause();
    }
}
