// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MockUSDC} from "./mocks/mockUSDC.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {GeniusVault} from "../src/GeniusVault.sol";
import {GeniusPool} from "../src/GeniusPool.sol";
import {GeniusExecutor} from "../src/GeniusExecutor.sol";

contract GeniusVaultTest is Test {

    address public permit2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address public owner = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;
    address public trader;

    MockUSDC public usdc;
    GeniusVault public geniusVault;
    GeniusPool public geniusPool;
    GeniusExecutor public executor;

    function setUp() public {
        trader = makeAddr("trader");
        usdc = new MockUSDC();

        vm.prank(owner);
        geniusVault = new GeniusVault(address(usdc), owner);

        vm.prank(owner);
        geniusPool = new GeniusPool(
            address(usdc),
            owner
        );

        executor = new GeniusExecutor(
            permit2,
            address(geniusPool),
            address(geniusVault)
        );

        vm.prank(owner);
        geniusVault.initialize(address(geniusPool));

        vm.prank(owner);
        geniusPool.initialize(address(geniusVault), address(executor));

        vm.prank(owner);
        usdc.mint(trader, 1_000 ether);
    }

    function testSelfDeposit() public {
        uint256 initialContractUSDCBalance = usdc.balanceOf(address(this));
        assertEq(initialContractUSDCBalance, 1_000_000 ether, "Initial balance should be 1,000 ether");

        usdc.approve(address(geniusVault), 1_000 ether);
        geniusVault.deposit(1_000 ether, address(this));

        assertEq(usdc.balanceOf(address(this)), 1_000_000 ether - 1_000 ether, "Contract balance should be 999,000 ether");
        assertEq(usdc.balanceOf(address(geniusVault)), 0, "GeniusVault balance should be 0");
        assertEq(usdc.balanceOf(address(geniusPool)), 1_000 ether, "GeniusPool balance should be 1,000 ether");

        uint256 totalAssets = geniusPool.totalAssets();
        uint256 availableAssets = geniusPool.availableAssets();
        uint256 totalStakedAssets = geniusPool.totalStakedAssets();

        uint256 vaultAssets = geniusVault.totalAssets();
        uint256 userShares = geniusVault.balanceOf(address(this));

        assertEq(totalAssets, 1_000 ether, "Total assets should be 1,000 ether");
        assertEq(totalStakedAssets, 1_000 ether, "Total staked assets should be 1,000 ether");
        assertEq(availableAssets, 750 ether, "Available assets should be 750 ether");
        assertEq(vaultAssets, 1_000 ether, "Vault assets should be 1,000 ether");
        assertEq(userShares, 1_000 ether, "User shares should be 1,000 ether");
    }


    function testDepositOnBehalfOf() public {
        uint256 usdcBalance = usdc.balanceOf(trader);
        uint256 geniusVaultBalance = usdc.balanceOf(address(geniusVault));

        assertEq(usdcBalance, 1_000 ether, "Trader should initially have 1,000 USDC");
        assertEq(geniusVaultBalance, 0, "GeniusVault should initially have 0 USDC");

        // Approve
        vm.prank(trader);
        usdc.approve(address(geniusVault), 1_000 ether);

        // Deposit
        vm.prank(trader);
        geniusVault.deposit(1_000 ether, trader);

        uint256 traderUSDCBalanceAfter = usdc.balanceOf(trader);

        assertEq(traderUSDCBalanceAfter, 0, "Trader's USDC balance should be 0 after deposit");
        assertEq(usdc.balanceOf(address(geniusVault)), 0, "GeniusVault's USDC balance should remain 0 after deposit if funds are redirected");
        assertEq(usdc.balanceOf(address(geniusPool)), 1_000 ether, "GeniusPool should have 1,000 USDC after deposit");

        uint256 totalAssets = geniusPool.totalAssets();
        uint256 availableAssets = geniusPool.availableAssets();
        uint256 totalStakedAssets = geniusPool.totalStakedAssets();

        assertEq(totalAssets, 1_000 ether, "Total assets in GeniusPool should be 1,000 USDC");
        assertEq(totalStakedAssets, 1_000 ether, "Total staked assets in GeniusPool should be 1,000 USDC");
        assertEq(availableAssets, 750 ether, "Available assets in GeniusPool should be 100 USDC, reflecting rebalance threshold");

        uint256 totalAssetsStaked = geniusVault.totalAssets();
        uint256 traderShares = geniusVault.balanceOf(trader);

        assertEq(totalAssetsStaked, 1_000 ether, "Total assets in GeniusVault should be 1,000 USDC after deposit");
        assertEq(traderShares, 1_000 ether, "Trader should hold shares equivalent to the USDC deposited in GeniusVault");
    }

    function testSelfDepositAndWithdraw() public {
        uint256 usdcBalance = usdc.balanceOf(address(this));
        assertEq(usdcBalance, 1_000_000 ether, "Contract should initially have 1,000,000 USDC");

        // Approve the GeniusVault to manage USDC on behalf of the contract
        usdc.approve(address(geniusVault), 1_000 ether);
        geniusVault.deposit(1_000 ether, address(this));
        geniusVault.approve(address(this), 1_000 ether);
        geniusVault.withdraw(1_000 ether, address(this), address(this));

        // Check the balance after withdrawal
        uint256 contractUSDCBalanceAfter = usdc.balanceOf(address(this));
        uint256 totalAssets = geniusPool.totalAssets();
        uint256 availableAssets = geniusPool.availableAssets();
        uint256 vaultAssets = geniusVault.totalAssets();

        assertEq(contractUSDCBalanceAfter, usdcBalance, "Contract's USDC should return to initial balance after withdrawal");
        assertEq(totalAssets, 0, "Total assets in the GeniusPool should be 0 after withdrawal");
        assertEq(availableAssets, 0, "Available assets in the GeniusPool should be 0 after withdrawal");
        assertEq(vaultAssets, 0, "Assets in the GeniusVault should be 0 after complete withdrawal");
    }

    function testDepositAndWithdrawOnBehalfOf() public {

        uint256 traderUSDCBalance = usdc.balanceOf(trader);
        assertEq(traderUSDCBalance, 1_000 ether, "Trader should initially have 1,000 USDC");

        vm.prank(trader);
        usdc.approve(address(geniusVault), 1_000 ether);

        vm.prank(trader);
        geniusVault.deposit(1_000 ether, trader);
        assertEq(usdc.balanceOf(trader), 0, "Trader's USDC should be 0 after deposit");

        vm.prank(trader);
        geniusVault.approve(trader, 1_000 ether);

        // Withdraw the deposited USDC back to the trader
        vm.prank(trader);
        geniusVault.withdraw(1_000 ether, trader, trader);

        // Check the balance after withdrawal
        uint256 traderUSDCBalanceAfter = usdc.balanceOf(trader);
        uint256 totalAssets = geniusPool.totalAssets();
        uint256 availableAssets = geniusPool.availableAssets();
        uint256 vaultAssets = geniusVault.totalAssets();

        assertEq(traderUSDCBalanceAfter, 1_000 ether, "Trader's USDC should return to initial balance after withdrawal");
        assertEq(totalAssets, 0, "Total assets in the GeniusPool should be 0 after withdrawal");
        assertEq(availableAssets, 0, "Available assets in the GeniusPool should be 0 after withdrawal");
        assertEq(vaultAssets, 0, "Assets in the GeniusVault should be 0 after complete withdrawal");
    }

    function testRevertDepositWithoutApproval() public {
        vm.prank(trader);
        vm.expectRevert("TRANSFER_FROM_FAILED");
        geniusVault.deposit(1_000 ether, trader);
    }

    function testWithdrawMoreThanDeposited() public {
        // First, approve and deposit some amount
        vm.prank(trader);
        usdc.approve(address(geniusVault), 500 ether);
        vm.prank(trader);
        geniusVault.deposit(500 ether, trader);

        vm.prank(trader);
        geniusVault.approve(trader, 1_000 ether);
        vm.expectRevert();
        vm.prank(trader);
        geniusVault.withdraw(1_000 ether, trader, trader);
    }
}
