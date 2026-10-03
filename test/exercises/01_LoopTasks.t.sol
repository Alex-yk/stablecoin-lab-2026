// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {MockUSDC} from "../../src/MockUSDC.sol";
import {SimpleStablecoin} from "../../src/SimpleStablecoin.sol";
import {Vault} from "../../src/Vault.sol";

/// @title Ex2 + Ex4 — hands-on tasks: turn red into green
/// @notice Every `assertTrue(false, "TODO ...")` below is a placeholder. Write the real
///         assertion, watch the test go green, and that exercise is done.
///
///         Acceptance: make exercise (it should be red until you are finished)
///         Do not open test/Stablecoin.t.sol — it contains the answers. Write yours
///         first, and only look once you are stuck.
contract LoopTasksTest is Test {
    MockUSDC internal usdc;
    SimpleStablecoin internal stable;
    Vault internal vault;

    address internal admin = address(this);
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal attacker = makeAddr("attacker");

    function setUp() public {
        usdc = new MockUSDC();
        stable = new SimpleStablecoin(admin);
        vault = new Vault(usdc, stable);
        stable.grantRole(stable.MINTER_ROLE(), address(vault));

        usdc.faucet(alice, 1_000_000e6);
    }

    // ==================================================================
    // Ex2 · the decimals trap: a 6-decimal stablecoin meets 18-decimal intuition
    // ==================================================================

    /// @dev For any legitimate amount x, totalSupply() must grow by exactly x after
    ///      deposit(x). Hint: use vm.assume to rule out x == 0, and faucet alice enough
    ///      usdc first.
    function test_Ex2_DepositIncreasesSupplyByExactly(uint96 raw) public {
        // vm 是 Foundry 测试框架提供的“作弊码（cheatcode）”接口，不是部署到链上的合约
        // vm.assume 排除金额为0的输入
        vm.assume(raw != 0);
        vm.assume(raw != 1_000_000e6);
        // 随机生成金额
        uint256 amount = uint256(raw) % 1_000_000e6;
        // 记录supply
        uint256 supplyBefore = stable.totalSupply();
        // 连续模拟扮演用户alice
        vm.startPrank(alice);
        // 1. approve to let the vault to move alice collateral
        usdc.approve(
            address(vault),
            amount
        );
        // 2. deposit: the valut mints amount to admin
        vault.deposit(amount);
        // 结束扮演
        vm.stopPrank();
        // 记录结束后的supply
        uint256 supplyAfter = stable.totalSupply();
        assertEq(
            supplyAfter - supplyBefore,
            amount
        );
    }

    /// @dev Run deposit with 1000e18 instead of 1000e6, see what happens, then assert what
    ///      you observed. MockUSDC has 6 decimals — 1000e18 is one billion USDC.
    ///      There is no expected answer here; the point is that you run it yourself and
    ///      read the numbers.
    function test_Ex2_DecimalsTrap() public {
        // for a contract, if 
        // - alice have enough balance
        // - allowance is approved
        // - amount != 0
        // then deposit should be execute correctly, no matter 1000 usdc or 10e15 usdc
        uint256 amount = 1000e18;

        usdc.faucet(alice, amount);

        uint256 supplyBefore = stable.totalSupply();
        uint256 collateralBefore = vault.totalCollateral();

        vm.startPrank(alice);
        usdc.approve(address(vault), amount);
        vault.deposit(amount);
        vm.stopPrank();

        uint256 supplyIncrease = stable.totalSupply() - supplyBefore;
        uint256 collateralIncrease = vault.totalCollateral() - collateralBefore;

        console2.log("Supply Increase: ", supplyIncrease);

        assertEq(supplyIncrease, amount);
        assertEq(collateralIncrease, amount);
    }

    // ==================================================================
    // Ex4 · permissions and pausing: where the guard is, who holds the key
    // ==================================================================

    /// @dev The attacker has no MINTER_ROLE, so calling mint directly must revert. Use
    ///      vm.expectRevert + abi.encodeWithSelector to pin down the exact error.
    function test_Ex4_Mint_RevertsForNonMinter() public {
        uint256 amount=1000e6;
        // make sure attacker do not have MINTER_ROLE
        assertFalse(stable.hasRole(stable.MINTER_ROLE(), attacker));

        // simulate attacker
        vm.startPrank(attacker);
        // 预期会有一个回滚
        vm.expectRevert();
        stable.mint(attacker, amount);

        vm.stopPrank();
    }

    /// @dev After pause(), an ordinary transfer must revert
    function test_Ex4_Pause_BlocksTransfers() public {
        uint256 amount=1000e6;
        uint256 transferAmount=100e6;

        // let alice hold stable
        usdc.faucet(alice, amount);

        vm.startPrank(alice);
        usdc.approve(address(vault), amount);
        vault.deposit(amount);
        vm.stopPrank();

        assertEq(stable.balanceOf(alice), amount);

        // admin pause stable
        vm.prank(admin);
        stable.pause();
        assertTrue(stable.paused());

        uint256 aliceBalanceBefore=stable.balanceOf(alice);
        uint256 bobBalanceBefore=stable.balanceOf(bob);

        // transfer must revert
        vm.startPrank(alice);
        vm.expectRevert();
        stable.transfer(bob, transferAmount);
        vm.stopPrank();
        
        assertEq(stable.balanceOf(alice), aliceBalanceBefore);
        assertEq(stable.balanceOf(bob), bobBalanceBefore);
    }

    /// @dev What pause() freezes is _update, so redemption is frozen along with everything
    ///      else — why is that bad news in a real crisis?
    ///      (This is STUDENT-QUESTIONS.md B1 and B2.)
    function test_Ex4_Pause_BlocksRedeem() public {
        uint256 amount=1000e6;

        // 1. alice 获取抵押品并正常存入 vault
        usdc.faucet(alice, amount);

        vm.startPrank(alice);
        usdc.approve(address(vault), amount);
        vault.deposit(amount);
        vm.stopPrank();

        assertEq(stable.balanceOf(alice), amount);

        // 记录暂停前的状态
        uint256 stableBalanceBefore = stable.balanceOf(alice);
        uint256 usdcBalanceBefore = usdc.balanceOf(alice);
        uint256 supplyBefore = stable.totalSupply();
        uint256 collateralBefore = vault.totalCollateral();

        // 管理员暂停stablecoin
        vm.prank(admin);
        stable.pause();

        assertTrue(stable.paused());

        // 3. alice尝试redeem，expectRevert
        vm.startPrank(alice);
        vm.expectRevert();
        vault.redeem(amount);
        vm.stopPrank();

        // 4. 交易回滚，所有状态应该不变
        assertEq(stable.balanceOf(alice), stableBalanceBefore);
        assertEq(usdc.balanceOf(alice), usdcBalanceBefore);
        assertEq(stable.totalSupply(), supplyBefore);
        assertEq(vault.totalCollateral(), collateralBefore);
    }

    /// @dev An attacker cannot burn someone else's balance
    function test_Ex4_AttackerCannotBurnOthersBalance() public {
        uint256 amount=1000e6;

        // alice获取余额
        usdc.faucet(alice, amount);

        vm.startPrank(alice);
        usdc.approve(address(vault), amount);
        vault.deposit(amount);
        vm.stopPrank();

        assertFalse(stable.hasRole(stable.MINTER_ROLE(), attacker));

        uint256 aliceBalanceBefore = stable.balanceOf(alice);
        uint256 supplyBefore = stable.totalSupply();

        // attacker尝试burn alice的余额，expectRevert
        vm.startPrank(attacker);
        vm.expectRevert();
        stable.burn(alice, amount);
        vm.stopPrank();


        // 余额和supply应该不变
        assertEq(stable.balanceOf(alice), aliceBalanceBefore);
        assertEq(stable.totalSupply(), supplyBefore);
    }

    /// @dev ...but the vault can, because it holds MINTER_ROLE and burn() answers to that
    ///      same role. This test proves the backdoor exists; it does not justify it.
    function test_Ex4_VaultHoldsTheKey_CanBurnAnyonesBalance() public {
        uint256 depositAmount=1000e6;
        uint256 burnAmount=300e6;

        // alice获取余额
        usdc.faucet(alice, depositAmount);

        vm.startPrank(alice);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);
        vm.stopPrank();

        // 确认 Vault 有MINTER_ROLE
        assertTrue(stable.hasRole(stable.MINTER_ROLE(), address(vault)));

        uint256 aliceBalanceBefore = stable.balanceOf(alice);
        uint256 supplyBefore = stable.totalSupply();
        uint256 collateralBefore = vault.totalCollateral();

        // vault burn alice的余额
        vm.prank(address(vault));
        stable.burn(alice, burnAmount);

        // alice余额和总供应量都减少了
        assertEq(stable.balanceOf(alice), aliceBalanceBefore - burnAmount);
        assertEq(stable.totalSupply(), supplyBefore - burnAmount);

        // 因为没有redeem，vault的deposit没有返还
        assertEq(vault.totalCollateral(), collateralBefore);
    }
}
