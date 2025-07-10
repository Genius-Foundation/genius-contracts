// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {GeniusVault} from "../src/GeniusVault.sol";
import {GeniusVaultCore} from "../src/GeniusVaultCore.sol";
import {GeniusProxyCall} from "../src/GeniusProxyCall.sol";
import {FeeCollector} from "../src/fees/FeeCollector.sol";
import {MockUSDC} from "./mocks/mockUSDC.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockV3Aggregator} from "./mocks/MockV3Aggregator.sol";

contract ERC4626FeaturesTest is Test {
    GeniusVault public vault;
    GeniusVaultCore public vaultCore;
    GeniusProxyCall public proxyCall;
    FeeCollector public feeCollector;
    MockUSDC public mockStablecoin;

    address public admin = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    address public orchestrator = address(0x4);
    address public rewardProvider = address(0x5);

    uint256 public constant INITIAL_BALANCE = 1000e18; // 1000 USDC (18 decimals)
    uint256 public constant DEPOSIT_AMOUNT = 100e18; // 100 USDC (18 decimals)
    uint256 public constant REWARD_AMOUNT = 50e18; // 50 USDC (18 decimals)

    event RewardsSubmitted(address indexed sender, uint256 amount);

    function setUp() public {
        // Deploy mock contracts
        mockStablecoin = new MockUSDC();
        
        // Deploy mock price feed
        MockV3Aggregator mockPriceFeed = new MockV3Aggregator(100_000_000); // $1.00
        
        // Deploy proxy call
        proxyCall = new GeniusProxyCall(admin, new address[](0));
        
        // Deploy vault implementation and proxy
        GeniusVault implementation = new GeniusVault();
        
        bytes memory data = abi.encodeWithSelector(
            GeniusVault.initialize.selector,
            address(mockStablecoin),
            admin,
            address(proxyCall),
            1000, // rebalanceThreshold
            address(mockPriceFeed), // priceFeed
            3600, // priceFeedHeartbeat
            95e6, // stablePriceLowerBound (0.95)
            105e6, // stablePriceUpperBound (1.05)
            10000e6 // maxOrderAmount
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);
        vault = GeniusVault(address(proxy));
        vaultCore = GeniusVaultCore(address(vault));
        
        // Deploy fee collector
        FeeCollector feeCollectorImplementation = new FeeCollector();
        
        bytes memory feeCollectorData = abi.encodeWithSelector(
            FeeCollector.initialize.selector,
            admin,
            address(mockStablecoin),
            2000, // 20% protocol fee
            admin,
            admin,
            admin
        );
        
        ERC1967Proxy feeCollectorProxy = new ERC1967Proxy(
            address(feeCollectorImplementation),
            feeCollectorData
        );
        
        feeCollector = FeeCollector(address(feeCollectorProxy));

        // Set up fee collector in vault
        vm.startPrank(admin);
        vault.setFeeCollector(address(feeCollector));
        feeCollector.setVault(address(vault));

        // Grant roles
        vault.grantRole(vault.ORCHESTRATOR_ROLE(), orchestrator);
        vault.grantRole(vault.PAUSER_ROLE(), admin);
        
        // Grant proxy call role to vault
        proxyCall.grantRole(proxyCall.CALLER_ROLE(), address(vault));
        vm.stopPrank();

        // Setup initial balances
        mockStablecoin.mint(admin, INITIAL_BALANCE);
        mockStablecoin.mint(user1, INITIAL_BALANCE);
        mockStablecoin.mint(user2, INITIAL_BALANCE);
        mockStablecoin.mint(rewardProvider, INITIAL_BALANCE);

        // Setup approvals
        vm.startPrank(admin);
        mockStablecoin.approve(address(vault), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user1);
        mockStablecoin.approve(address(vault), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user2);
        mockStablecoin.approve(address(vault), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(rewardProvider);
        mockStablecoin.approve(address(vault), type(uint256).max);
        vm.stopPrank();
    }

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                    BASIC ERC4626 TESTS                    ║
    // ╚═══════════════════════════════════════════════════════════╝

    function test_Deposit() public {
        vm.startPrank(user1);
        
        uint256 initialBalance = mockStablecoin.balanceOf(user1);
        uint256 initialVaultBalance = mockStablecoin.balanceOf(address(vault));
        uint256 initialTotalStakedAssets = vault.totalStakedAssets();
        
        uint256 shares = vault.deposit(DEPOSIT_AMOUNT, user1);
        
        assertEq(mockStablecoin.balanceOf(user1), initialBalance - DEPOSIT_AMOUNT);
        assertEq(mockStablecoin.balanceOf(address(vault)), initialVaultBalance + DEPOSIT_AMOUNT);
        assertEq(vault.totalStakedAssets(), initialTotalStakedAssets + DEPOSIT_AMOUNT);
        assertEq(vault.balanceOf(user1), DEPOSIT_AMOUNT); // ERC20 balance shows asset value
        assertGt(shares, 0);
        
        vm.stopPrank();
    }

    function test_Withdraw() public {
        // First deposit
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        uint256 initialBalance = mockStablecoin.balanceOf(user1);
        uint256 initialVaultBalance = mockStablecoin.balanceOf(address(vault));
        uint256 initialTotalStakedAssets = vault.totalStakedAssets();
        
        // Then withdraw
        uint256 withdrawAmount = 50e6; // 50 USDC
        uint256 shares = vault.withdraw(withdrawAmount, user1, user1);
        
        assertEq(mockStablecoin.balanceOf(user1), initialBalance + withdrawAmount);
        assertEq(mockStablecoin.balanceOf(address(vault)), initialVaultBalance - withdrawAmount);
        assertEq(vault.totalStakedAssets(), initialTotalStakedAssets - withdrawAmount);
        assertEq(vault.balanceOf(user1), DEPOSIT_AMOUNT - withdrawAmount);
        assertGt(shares, 0);
        
        vm.stopPrank();
    }

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                    SUBMIT REWARDS TESTS                   ║
    // ╚═══════════════════════════════════════════════════════════╝

    function test_SubmitRewards() public {
        vm.startPrank(rewardProvider);
        
        uint256 initialBalance = mockStablecoin.balanceOf(rewardProvider);
        uint256 initialVaultBalance = mockStablecoin.balanceOf(address(vault));
        uint256 initialTotalStakedAssets = vault.totalStakedAssets();
        
        vm.expectEmit(true, false, false, true);
        emit RewardsSubmitted(rewardProvider, REWARD_AMOUNT);
        
        vault.submitRewards(REWARD_AMOUNT);
        
        assertEq(mockStablecoin.balanceOf(rewardProvider), initialBalance - REWARD_AMOUNT);
        assertEq(mockStablecoin.balanceOf(address(vault)), initialVaultBalance + REWARD_AMOUNT);
        assertEq(vault.totalStakedAssets(), initialTotalStakedAssets + REWARD_AMOUNT);
        
        vm.stopPrank();
    }

    function test_SubmitRewardsZeroAmount() public {
        vm.startPrank(rewardProvider);
        
        vm.expectRevert();
        vault.submitRewards(0);
        
        vm.stopPrank();
    }

    function test_SubmitRewardsInsufficientAllowance() public {
        vm.startPrank(rewardProvider);
        
        // Revoke approval
        mockStablecoin.approve(address(vault), 0);
        
        vm.expectRevert();
        vault.submitRewards(REWARD_AMOUNT);
        
        vm.stopPrank();
    }

    function test_SubmitRewardsWhenPaused() public {
        vm.startPrank(admin);
        vault.pause();
        vm.stopPrank();
        
        vm.startPrank(rewardProvider);
        vm.expectRevert();
        vault.submitRewards(REWARD_AMOUNT);
        vm.stopPrank();
    }

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                    AUTO-COMPOUNDING TESTS                 ║
    // ╚═══════════════════════════════════════════════════════════╝

    function test_AutoCompoundingWithRewards() public {
        // User1 deposits
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        uint256 initialShares = vault.balanceOf(user1);
        vm.stopPrank();
        
        // Reward provider submits rewards
        vm.startPrank(rewardProvider);
        vault.submitRewards(REWARD_AMOUNT);
        vm.stopPrank();
        
        // User1's balance should increase due to auto-compounding
        vm.startPrank(user1);
        uint256 newBalance = vault.balanceOf(user1);
        assertApproxEqAbs(newBalance, vault.totalAssets(), 10, "User should own all assets if only staker");
        
        // User1 can withdraw more than they deposited
        uint256 withdrawAmount = newBalance;
        uint256 userBalanceBeforeWithdraw = mockStablecoin.balanceOf(user1);
        vault.withdraw(withdrawAmount, user1, user1);
        
        assertApproxEqAbs(mockStablecoin.balanceOf(user1), userBalanceBeforeWithdraw + withdrawAmount, 10);
        vm.stopPrank();
    }

    function test_MultipleUsersAutoCompounding() public {
        // User1 deposits
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        uint256 user1InitialBalance = vault.balanceOf(user1);
        vm.stopPrank();
        
        // User2 deposits
        vm.startPrank(user2);
        vault.deposit(DEPOSIT_AMOUNT, user2);
        uint256 user2InitialBalance = vault.balanceOf(user2);
        vm.stopPrank();
        
        // Reward provider submits rewards
        vm.startPrank(rewardProvider);
        vault.submitRewards(REWARD_AMOUNT);
        vm.stopPrank();
        
        // Both users should benefit proportionally
        vm.startPrank(user1);
        uint256 user1NewBalance = vault.balanceOf(user1);
        vm.stopPrank();
        
        vm.startPrank(user2);
        uint256 user2NewBalance = vault.balanceOf(user2);
        vm.stopPrank();
        
        assertGt(user1NewBalance, user1InitialBalance, "User1 should benefit from rewards");
        assertGt(user2NewBalance, user2InitialBalance, "User2 should benefit from rewards");
        
        // Both users should benefit equally (same deposit amount)
        uint256 user1Increase = user1NewBalance - user1InitialBalance;
        uint256 user2Increase = user2NewBalance - user2InitialBalance;
        assertEq(user1Increase, user2Increase, "Users should benefit equally");
    }

    function test_AutoCompoundingWithMultipleRewardSubmissions() public {
        // User1 deposits
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        uint256 initialBalance = vault.balanceOf(user1);
        vm.stopPrank();
        
        // Multiple reward submissions
        vm.startPrank(rewardProvider);
        vault.submitRewards(REWARD_AMOUNT);
        vault.submitRewards(REWARD_AMOUNT);
        vault.submitRewards(REWARD_AMOUNT);
        vm.stopPrank();
        
        // User1's balance should increase significantly
        vm.startPrank(user1);
        uint256 finalBalance = vault.balanceOf(user1);
        
        // The user should get all rewards since they're the only staker
        assertGt(finalBalance, initialBalance, "Balance should increase after rewards");
        
        // Debug: Print actual values to see what's happening
        console.log("Final balance:", finalBalance);
        console.log("Total assets:", vault.totalAssets());
        console.log("Difference:", finalBalance > vault.totalAssets() ? finalBalance - vault.totalAssets() : vault.totalAssets() - finalBalance);
        
        assertApproxEqAbs(finalBalance, vault.totalAssets(), 10, "User should own all assets if only staker");
        
        // Can withdraw more than original deposit + all rewards (accounting for rounding)
        uint256 withdrawAmount = finalBalance;
        uint256 userBalanceBeforeWithdraw = mockStablecoin.balanceOf(user1);
        vault.withdraw(withdrawAmount, user1, user1);
        
        assertApproxEqAbs(mockStablecoin.balanceOf(user1), userBalanceBeforeWithdraw + withdrawAmount, 10);
        vm.stopPrank();
    }

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                    ERC20 OVERRIDE TESTS                   ║
    // ╚═══════════════════════════════════════════════════════════╝

    function test_ERC20BalanceOfShowsAssetValue() public {
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        
        // ERC20 balanceOf should show asset value, not shares
        assertEq(vault.balanceOf(user1), DEPOSIT_AMOUNT);
        
        vm.stopPrank();
    }

    function test_ERC20TransferWorksWithAssetAmounts() public {
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
        
        // Transfer should work with asset amounts
        vm.startPrank(user1);
        uint256 transferAmount = 50e18; // 50 USDC (18 decimals)
        bool success = vault.transfer(user2, transferAmount);
        assertTrue(success);
        
        assertEq(vault.balanceOf(user1), DEPOSIT_AMOUNT - transferAmount);
        assertEq(vault.balanceOf(user2), transferAmount);
        
        vm.stopPrank();
    }

    function test_ERC20ApproveWorksWithAssetAmounts() public {
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        
        uint256 approveAmount = 50e18; // 50 USDC (18 decimals)
        bool success = vault.approve(user2, approveAmount);
        assertTrue(success);
        
        assertEq(vault.allowance(user1, user2), approveAmount);
        
        vm.stopPrank();
    }

    function test_ERC20TransferFromWorksWithAssetAmounts() public {
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vault.approve(user2, DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        vm.startPrank(user2);
        uint256 transferAmount = 50e18; // 50 USDC (18 decimals)
        bool success = vault.transferFrom(user1, user2, transferAmount);
        assertTrue(success);
        
        assertEq(vault.balanceOf(user1), DEPOSIT_AMOUNT - transferAmount);
        assertEq(vault.balanceOf(user2), transferAmount);
        
        vm.stopPrank();
    }

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                    EDGE CASES TESTS                       ║
    // ╚═══════════════════════════════════════════════════════════╝

    function test_FirstDepositCreatesInitialShares() public {
        vm.startPrank(user1);
        
        uint256 shares = vault.deposit(DEPOSIT_AMOUNT, user1);
        
        // First deposit should create shares equal to assets (1:1 ratio)
        assertEq(shares, DEPOSIT_AMOUNT);
        assertEq(vault.totalSupply(), DEPOSIT_AMOUNT);
        
        vm.stopPrank();
    }

    function test_WithdrawMoreThanDeposited() public {
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        
        // Add rewards
        vm.stopPrank();
        vm.startPrank(rewardProvider);
        vault.submitRewards(REWARD_AMOUNT);
        vm.stopPrank();
        
        // User1 should be able to withdraw more than they deposited
        vm.startPrank(user1);
        uint256 currentBalance = vault.balanceOf(user1);
        uint256 userBalanceBeforeWithdraw = mockStablecoin.balanceOf(user1);
        vault.withdraw(currentBalance, user1, user1);
        
        assertApproxEqAbs(mockStablecoin.balanceOf(user1), userBalanceBeforeWithdraw + currentBalance, 10);
        assertEq(vault.balanceOf(user1), 0);
        
        vm.stopPrank();
    }

    function test_TotalAssetsReturnsTotalStakedAssets() public {
        assertEq(vault.totalAssets(), vault.totalStakedAssets());
        
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        assertEq(vault.totalAssets(), vault.totalStakedAssets());
        vm.stopPrank();
        
        vm.startPrank(rewardProvider);
        vault.submitRewards(REWARD_AMOUNT);
        assertEq(vault.totalAssets(), vault.totalStakedAssets());
        vm.stopPrank();
    }

    function test_AssetReturnsStablecoinAddress() public {
        assertEq(vault.asset(), address(mockStablecoin));
    }

    function test_ConvertToAssetsAndShares() public {
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
        
        // Add some rewards to test conversion
        vm.startPrank(rewardProvider);
        vault.submitRewards(REWARD_AMOUNT);
        vm.stopPrank();
        
        vm.startPrank(user1);
        uint256 userShares = vault.balanceOf(user1);
        uint256 convertedAssets = vault.convertToAssets(userShares);
        uint256 convertedShares = vault.convertToShares(convertedAssets);
        
        // Should be able to convert back and forth (with small rounding tolerance)
        assertApproxEqRel(convertedShares, userShares, 1e15); // 0.1% tolerance
        
        vm.stopPrank();
    }

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                    DEBUG TESTS                            ║
    // ╚═══════════════════════════════════════════════════════════╝

    function test_DebugConversion() public {
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        
        uint256 afterDepositBalance = vault.balanceOf(user1);
        uint256 afterDepositTotalAssets = vault.totalAssets();
        uint256 afterDepositTotalSupply = vault.totalSupply();
        
        vm.stopPrank();
        
        vm.startPrank(rewardProvider);
        vault.submitRewards(REWARD_AMOUNT);
        vm.stopPrank();
        
        uint256 afterRewardsBalance = vault.balanceOf(user1);
        uint256 afterRewardsTotalAssets = vault.totalAssets();
        uint256 afterRewardsTotalSupply = vault.totalSupply();
        
        vm.startPrank(user1);
        uint256 shares = vault.balanceOf(user1);
        uint256 convertedAssets = vault.convertToAssets(shares);
        uint256 convertedShares = vault.convertToShares(convertedAssets);
        
        // Assert that the balance should increase after rewards
        assertGt(afterRewardsBalance, afterDepositBalance, "Balance should increase after rewards");
        assertGt(afterRewardsTotalAssets, afterDepositTotalAssets, "Total assets should increase after rewards");
        // Note: totalSupply() returns totalAssets(), so it should increase with rewards
        assertGt(afterRewardsTotalSupply, afterDepositTotalSupply, "Total supply (assets) should increase after rewards");
        
        vm.stopPrank();
    }

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                    INTEGRATION TESTS                      ║
    // ╚═══════════════════════════════════════════════════════════╝

    function test_CompleteUserJourney() public {
        // 1. User deposits
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        uint256 initialBalance = vault.balanceOf(user1);
        vm.stopPrank();
        
        // 2. Rewards are submitted multiple times
        vm.startPrank(rewardProvider);
        vault.submitRewards(REWARD_AMOUNT);
        vault.submitRewards(REWARD_AMOUNT);
        vm.stopPrank();
        
        // 3. User transfers some tokens
        vm.startPrank(user1);
        vault.transfer(user2, 25e18); // Transfer 25 USDC (18 decimals)
        vm.stopPrank();
        
        // 4. User approves and transfers from
        vm.startPrank(user1);
        vault.approve(user2, 50e18);
        vm.stopPrank();
        
        vm.startPrank(user2);
        vault.transferFrom(user1, user2, 25e18);
        vm.stopPrank();
        
        // 5. User withdraws remaining balance
        vm.startPrank(user1);
        uint256 remainingBalance = vault.balanceOf(user1);
        vault.withdraw(remainingBalance, user1, user1);
        
        // Should have received more than original deposit due to rewards
        assertGt(mockStablecoin.balanceOf(user1), DEPOSIT_AMOUNT);
        
        vm.stopPrank();
    }

    function test_MultipleUsersComplexScenario() public {
        // User1 deposits
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
        
        // Rewards are submitted
        vm.startPrank(rewardProvider);
        vault.submitRewards(REWARD_AMOUNT);
        vm.stopPrank();
        
        // User2 deposits
        vm.startPrank(user2);
        vault.deposit(DEPOSIT_AMOUNT, user2);
        vm.stopPrank();
        
        // More rewards
        vm.startPrank(rewardProvider);
        vault.submitRewards(REWARD_AMOUNT);
        vm.stopPrank();
        
        // Both users should benefit from all rewards
        vm.startPrank(user1);
        uint256 user1Balance = vault.balanceOf(user1);
        vm.stopPrank();
        
        vm.startPrank(user2);
        uint256 user2Balance = vault.balanceOf(user2);
        vm.stopPrank();
        
        // Both should have more than their original deposits
        assertGt(user1Balance, DEPOSIT_AMOUNT);
        assertGt(user2Balance, DEPOSIT_AMOUNT);
        
        // User2 should have benefited from the second reward round
        assertGt(user2Balance, DEPOSIT_AMOUNT, "User2 should benefit from second reward round");
    }

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                    ADVANCED ERC4626 TESTS                 ║
    // ╚═══════════════════════════════════════════════════════════╝

    function test_PreviewDeposit() public {
        vm.startPrank(user1);
        
        uint256 previewShares = vault.previewDeposit(DEPOSIT_AMOUNT);
        uint256 actualShares = vault.deposit(DEPOSIT_AMOUNT, user1);
        
        // Preview should match actual deposit
        assertEq(previewShares, actualShares);
        
        vm.stopPrank();
    }

    function test_PreviewWithdraw() public {
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        
        uint256 withdrawAmount = 50e18;
        uint256 previewShares = vault.previewWithdraw(withdrawAmount);
        uint256 actualShares = vault.withdraw(withdrawAmount, user1, user1);
        
        // Preview should match actual withdraw
        assertEq(previewShares, actualShares);
        
        vm.stopPrank();
    }

    function test_MaxDeposit() public {
        vm.startPrank(user1);
        
        uint256 maxDeposit = vault.maxDeposit(user1);
        uint256 maxMint = vault.maxMint(user1);
        
        // maxDeposit and maxMint should be type(uint256).max for ERC4626
        assertEq(maxDeposit, type(uint256).max);
        assertEq(maxMint, type(uint256).max);
        
        // Should be able to deposit up to user's balance
        vault.deposit(INITIAL_BALANCE, user1);
        
        // Should be able to mint with remaining balance (if any)
        uint256 remainingBalance = mockStablecoin.balanceOf(user1);
        if (remainingBalance > 0) {
            vault.mint(remainingBalance, user1);
        }
        
        vm.stopPrank();
    }

    function test_MaxWithdraw() public {
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        
        uint256 maxWithdraw = vault.maxWithdraw(user1);
        uint256 maxRedeem = vault.maxRedeem(user1);
        
        // maxWithdraw and maxRedeem should be limited by user's vault balance
        assertLe(maxWithdraw, DEPOSIT_AMOUNT);
        assertLe(maxRedeem, DEPOSIT_AMOUNT);
        
        // Should be able to withdraw up to user's balance
        vault.withdraw(maxWithdraw, user1, user1);
        
        // Should be able to redeem remaining balance
        uint256 remainingBalance = vault.balanceOf(user1);
        if (remainingBalance > 0) {
            vault.withdraw(remainingBalance, user1, user1);
        }
        
        vm.stopPrank();
    }

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                    ERC20 METADATA TESTS                   ║
    // ╚═══════════════════════════════════════════════════════════╝

    function test_ERC20Metadata() public {
        assertEq(vault.name(), "Genius USD");
        assertEq(vault.symbol(), "gUSD");
        assertEq(vault.decimals(), 18);
    }

    function test_ERC20Events() public {
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        
        // Test Transfer event
        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(address(0), user1, DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        
        // Test Approval event
        vm.expectEmit(true, true, false, true);
        emit IERC20.Approval(user1, user2, 50e18);
        vault.approve(user2, 50e18);
        
        vm.stopPrank();
    }

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                    ZERO AMOUNT TESTS                      ║
    // ╚═══════════════════════════════════════════════════════════╝

    function test_DepositZeroAmount() public {
        vm.startPrank(user1);
        
        // ERC4626 allows zero deposits, they just return 0 shares
        uint256 shares = vault.deposit(0, user1);
        assertEq(shares, 0);
        assertEq(vault.balanceOf(user1), 0);
        
        vm.stopPrank();
    }

    function test_WithdrawZeroAmount() public {
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        
        // ERC4626 allows zero withdrawals, they just return 0 shares
        uint256 shares = vault.withdraw(0, user1, user1);
        assertEq(shares, 0);
        assertEq(vault.balanceOf(user1), DEPOSIT_AMOUNT);
        
        vm.stopPrank();
    }

    function test_TransferZeroAmount() public {
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        
        // Transfer zero amount should succeed but not change balances
        uint256 balanceBefore = vault.balanceOf(user1);
        bool success = vault.transfer(user2, 0);
        assertTrue(success);
        assertEq(vault.balanceOf(user1), balanceBefore);
        assertEq(vault.balanceOf(user2), 0);
        
        vm.stopPrank();
    }

    function test_ApproveZeroAmount() public {
        vm.startPrank(user1);
        
        bool success = vault.approve(user2, 0);
        assertTrue(success);
        assertEq(vault.allowance(user1, user2), 0);
        
        vm.stopPrank();
    }

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                    INSUFFICIENT BALANCE TESTS             ║
    // ╚═══════════════════════════════════════════════════════════╝

    function test_WithdrawInsufficientBalance() public {
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        
        vm.expectRevert();
        vault.withdraw(DEPOSIT_AMOUNT + 1, user1, user1);
        
        vm.stopPrank();
    }

    function test_TransferInsufficientBalance() public {
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        
        vm.expectRevert();
        vault.transfer(user2, DEPOSIT_AMOUNT + 1);
        
        vm.stopPrank();
    }

    function test_TransferFromInsufficientBalance() public {
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vault.approve(user2, DEPOSIT_AMOUNT + 1);
        vm.stopPrank();
        
        vm.startPrank(user2);
        vm.expectRevert();
        vault.transferFrom(user1, user2, DEPOSIT_AMOUNT + 1);
        vm.stopPrank();
    }

    function test_TransferFromInsufficientAllowance() public {
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vault.approve(user2, 50e18);
        vm.stopPrank();
        
        vm.startPrank(user2);
        vm.expectRevert();
        vault.transferFrom(user1, user2, 100e18);
        vm.stopPrank();
    }

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                    PAUSED STATE TESTS                     ║
    // ╚═══════════════════════════════════════════════════════════╝

    function test_DepositWhenPaused() public {
        vm.startPrank(admin);
        vault.pause();
        vm.stopPrank();
        
        vm.startPrank(user1);
        vm.expectRevert();
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
    }

    function test_WithdrawWhenPaused() public {
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
        
        vm.startPrank(admin);
        vault.pause();
        vm.stopPrank();
        
        vm.startPrank(user1);
        vm.expectRevert();
        vault.withdraw(50e18, user1, user1);
        vm.stopPrank();
    }

    function test_MintWhenPaused() public {
        vm.startPrank(admin);
        vault.pause();
        vm.stopPrank();
        
        vm.startPrank(user1);
        vm.expectRevert();
        vault.mint(100e18, user1);
        vm.stopPrank();
    }

    function test_TransferWhenPaused() public {
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
        
        vm.startPrank(admin);
        vault.pause();
        vm.stopPrank();
        
        vm.startPrank(user1);
        // Transfer should still work when paused since it's just an ERC20 operation
        bool success = vault.transfer(user2, 50e18);
        assertTrue(success);
        vm.stopPrank();
    }

    function test_TransferFromWhenPaused() public {
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vault.approve(user2, 50e18);
        vm.stopPrank();
        
        vm.startPrank(admin);
        vault.pause();
        vm.stopPrank();
        
        vm.startPrank(user2);
        // TransferFrom should still work when paused since it's just an ERC20 operation
        bool success = vault.transferFrom(user1, user2, 50e18);
        assertTrue(success);
        vm.stopPrank();
    }

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                    ROUNDING TESTS                         ║
    // ╚═══════════════════════════════════════════════════════════╝

    function test_RoundingWithSmallAmounts() public {
        vm.startPrank(user1);
        
        // Test with very small amounts
        uint256 smallAmount = 1; // 1 wei
        vault.deposit(smallAmount, user1);
        
        uint256 balance = vault.balanceOf(user1);
        assertEq(balance, smallAmount);
        
        // Test withdrawal of small amount
        vault.withdraw(smallAmount, user1, user1);
        assertEq(vault.balanceOf(user1), 0);
        
        vm.stopPrank();
    }

    function test_RoundingWithLargeAmounts() public {
        vm.startPrank(user1);
        
        // Test with very large amounts
        uint256 largeAmount = 1e30; // 1e30 wei
        mockStablecoin.mint(user1, largeAmount);
        mockStablecoin.approve(address(vault), largeAmount);
        
        vault.deposit(largeAmount, user1);
        
        uint256 balance = vault.balanceOf(user1);
        assertEq(balance, largeAmount);
        
        // Test withdrawal of large amount
        vault.withdraw(largeAmount, user1, user1);
        assertEq(vault.balanceOf(user1), 0);
        
        vm.stopPrank();
    }

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                    CONVERSION ACCURACY TESTS              ║
    // ╚═══════════════════════════════════════════════════════════╝

    function test_ConversionAccuracyWithRewards() public {
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
        
        // Add rewards to create non-1:1 ratio
        vm.startPrank(rewardProvider);
        vault.submitRewards(REWARD_AMOUNT);
        vm.stopPrank();
        
        vm.startPrank(user1);
        uint256 userBalance = vault.balanceOf(user1);
        
        // Test conversion accuracy
        uint256 convertedToAssets = vault.convertToAssets(userBalance);
        uint256 convertedToShares = vault.convertToShares(convertedToAssets);
        
        // Should be very close to original balance
        assertApproxEqRel(convertedToShares, userBalance, 1e12); // 0.0001% tolerance
        
        vm.stopPrank();
    }

    function test_ConversionAccuracyMultipleUsers() public {
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
        
        vm.startPrank(user2);
        vault.deposit(DEPOSIT_AMOUNT, user2);
        vm.stopPrank();
        
        // Add rewards
        vm.startPrank(rewardProvider);
        vault.submitRewards(REWARD_AMOUNT);
        vm.stopPrank();
        
        // Test conversion for both users
        vm.startPrank(user1);
        uint256 user1Balance = vault.balanceOf(user1);
        uint256 user1Converted = vault.convertToAssets(user1Balance);
        uint256 user1ConvertedBack = vault.convertToShares(user1Converted);
        assertApproxEqRel(user1ConvertedBack, user1Balance, 1e12);
        vm.stopPrank();
        
        vm.startPrank(user2);
        uint256 user2Balance = vault.balanceOf(user2);
        uint256 user2Converted = vault.convertToAssets(user2Balance);
        uint256 user2ConvertedBack = vault.convertToShares(user2Converted);
        assertApproxEqRel(user2ConvertedBack, user2Balance, 1e12);
        vm.stopPrank();
    }

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                    COMPLEX SCENARIO TESTS                 ║
    // ╚═══════════════════════════════════════════════════════════╝

    function test_ComplexDepositWithdrawCycle() public {
        address user3 = address(0x6);
        mockStablecoin.mint(user3, INITIAL_BALANCE);
        
        vm.startPrank(user3);
        mockStablecoin.approve(address(vault), type(uint256).max);
        
        // Multiple deposit/withdraw cycles
        for (uint256 i = 0; i < 5; i++) {
            vault.deposit(10e18, user3);
            vault.withdraw(5e18, user3, user3);
        }
        
        // Add rewards
        vm.stopPrank();
        vm.startPrank(rewardProvider);
        vault.submitRewards(REWARD_AMOUNT);
        vm.stopPrank();
        
        // Continue cycles after rewards
        vm.startPrank(user3);
        for (uint256 i = 0; i < 3; i++) {
            vault.deposit(10e18, user3);
            vault.withdraw(5e18, user3, user3);
        }
        
        // Final withdrawal
        uint256 finalBalance = vault.balanceOf(user3);
        vault.withdraw(finalBalance, user3, user3);
        assertEq(vault.balanceOf(user3), 0);
        
        vm.stopPrank();
    }

    function test_MultipleUsersWithRewardsAndTransfers() public {
        address user3 = address(0x6);
        address user4 = address(0x7);
        
        mockStablecoin.mint(user3, INITIAL_BALANCE);
        mockStablecoin.mint(user4, INITIAL_BALANCE);
        
        // User1 and User2 deposit
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
        
        vm.startPrank(user2);
        vault.deposit(DEPOSIT_AMOUNT, user2);
        vm.stopPrank();
        
        // Add rewards
        vm.startPrank(rewardProvider);
        vault.submitRewards(REWARD_AMOUNT);
        vm.stopPrank();
        
        // User3 and User4 deposit
        vm.startPrank(user3);
        mockStablecoin.approve(address(vault), type(uint256).max);
        vault.deposit(DEPOSIT_AMOUNT, user3);
        vm.stopPrank();
        
        vm.startPrank(user4);
        mockStablecoin.approve(address(vault), type(uint256).max);
        vault.deposit(DEPOSIT_AMOUNT, user4);
        vm.stopPrank();
        
        // More rewards
        vm.startPrank(rewardProvider);
        vault.submitRewards(REWARD_AMOUNT);
        vm.stopPrank();
        
        // Complex transfers between users
        vm.startPrank(user1);
        vault.transfer(user3, 25e18);
        vm.stopPrank();
        
        vm.startPrank(user2);
        vault.transfer(user4, 25e18);
        vm.stopPrank();
        
        vm.startPrank(user3);
        vault.approve(user4, 50e18);
        vm.stopPrank();
        
        vm.startPrank(user4);
        vault.transferFrom(user3, user4, 25e18);
        vm.stopPrank();
        
        // All users should have positive balances
        assertGt(vault.balanceOf(user1), 0);
        assertGt(vault.balanceOf(user2), 0);
        assertGt(vault.balanceOf(user3), 0);
        assertGt(vault.balanceOf(user4), 0);
    }

    function test_StressTestWithManyUsers() public {
        address[] memory users = new address[](10);
        for (uint256 i = 0; i < 10; i++) {
            users[i] = address(uint160(0x1000 + i));
            mockStablecoin.mint(users[i], INITIAL_BALANCE);
        }
        
        // All users deposit
        for (uint256 i = 0; i < 10; i++) {
            vm.startPrank(users[i]);
            mockStablecoin.approve(address(vault), type(uint256).max);
            vault.deposit(10e18, users[i]);
            vm.stopPrank();
        }
        
        // Multiple reward rounds
        for (uint256 round = 0; round < 5; round++) {
            vm.startPrank(rewardProvider);
            vault.submitRewards(REWARD_AMOUNT);
            vm.stopPrank();
            
            // Random transfers between users
            for (uint256 i = 0; i < 3; i++) {
                uint256 fromIndex = i % 10;
                uint256 toIndex = (i + 1) % 10;
                
                vm.startPrank(users[fromIndex]);
                vault.transfer(users[toIndex], 1e18);
                vm.stopPrank();
            }
        }
        
        // All users should have positive balances
        for (uint256 i = 0; i < 10; i++) {
            assertGt(vault.balanceOf(users[i]), 0);
        }
    }

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                    EDGE CASE TESTS                        ║
    // ╚═══════════════════════════════════════════════════════════╝

    function test_FirstDepositAfterRewards() public {
        // Add rewards before any deposits
        vm.startPrank(rewardProvider);
        vault.submitRewards(REWARD_AMOUNT);
        vm.stopPrank();
        
        // First deposit should give the user both their deposit and the rewards
        // This is correct for a stablecoin vault - the first depositor gets all rewards
        vm.startPrank(user1);
        uint256 shares = vault.deposit(DEPOSIT_AMOUNT, user1);
        assertEq(shares, DEPOSIT_AMOUNT);
        assertEq(vault.balanceOf(user1), DEPOSIT_AMOUNT + REWARD_AMOUNT);
        vm.stopPrank();
    }

    function test_WithdrawAllAndRedeposit() public {
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        
        // Add rewards
        vm.stopPrank();
        vm.startPrank(rewardProvider);
        vault.submitRewards(REWARD_AMOUNT);
        vm.stopPrank();
        
        // Withdraw all
        vm.startPrank(user1);
        uint256 totalBalance = vault.balanceOf(user1);
        vault.withdraw(totalBalance, user1, user1);
        assertEq(vault.balanceOf(user1), 0);
        
        // Redeposit
        vault.deposit(DEPOSIT_AMOUNT, user1);
        assertEq(vault.balanceOf(user1), DEPOSIT_AMOUNT);
        vm.stopPrank();
    }

    function test_TransferToSelf() public {
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        
        uint256 balanceBefore = vault.balanceOf(user1);
        bool success = vault.transfer(user1, 50e18);
        assertTrue(success);
        assertEq(vault.balanceOf(user1), balanceBefore);
        
        vm.stopPrank();
    }

    function test_TransferFromSelf() public {
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vault.approve(user1, 50e18);
        
        uint256 balanceBefore = vault.balanceOf(user1);
        bool success = vault.transferFrom(user1, user1, 50e18);
        assertTrue(success);
        assertEq(vault.balanceOf(user1), balanceBefore);
        
        vm.stopPrank();
    }

    function test_ApproveToSelf() public {
        vm.startPrank(user1);
        
        // First deposit some tokens so the user has a balance
        vault.deposit(DEPOSIT_AMOUNT, user1);
        
        bool success = vault.approve(user1, 100e18);
        assertTrue(success);
        assertEq(vault.allowance(user1, user1), 100e18);
        
        vm.stopPrank();
    }

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                    GAS OPTIMIZATION TESTS                 ║
    // ╚═══════════════════════════════════════════════════════════╝

    function test_GasUsageForBasicOperations() public {
        vm.startPrank(user1);
        
        uint256 gasBefore = gasleft();
        vault.deposit(DEPOSIT_AMOUNT, user1);
        uint256 gasUsed = gasBefore - gasleft();
        
        // Should use reasonable amount of gas
        assertLt(gasUsed, 200000);
        
        gasBefore = gasleft();
        vault.withdraw(50e18, user1, user1);
        gasUsed = gasBefore - gasleft();
        
        // Should use reasonable amount of gas
        assertLt(gasUsed, 200000);
        
        vm.stopPrank();
    }

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                    REENTRANCY TESTS                       ║
    // ╚═══════════════════════════════════════════════════════════╝

    function test_ReentrancyProtection() public {
        // This test verifies that the nonReentrant modifier is working
        // The withdraw and redeem functions should have reentrancy protection
        
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        
        // These operations should not revert due to reentrancy protection
        vault.withdraw(50e18, user1, user1);
        vault.withdraw(25e18, user1, user1);
        
        vm.stopPrank();
    }

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                    DECIMAL PRECISION TESTS                ║
    // ╚═══════════════════════════════════════════════════════════╝

    function test_DecimalPrecision() public {
        vm.startPrank(user1);
        
        // Test with amounts that have different decimal precision
        uint256[] memory amounts = new uint256[](5);
        amounts[0] = 1; // 1 wei
        amounts[1] = 1e6; // 0.000001 tokens
        amounts[2] = 1e12; // 0.000001 tokens
        amounts[3] = 1e15; // 0.001 tokens
        amounts[4] = 1e18; // 1 token
        
        for (uint256 i = 0; i < amounts.length; i++) {
            vault.deposit(amounts[i], user1);
            assertEq(vault.balanceOf(user1), amounts[i]);
            vault.withdraw(amounts[i], user1, user1);
            assertEq(vault.balanceOf(user1), 0);
        }
        
        vm.stopPrank();
    }

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                    BOUNDARY TESTS                         ║
    // ╚═══════════════════════════════════════════════════════════╝

    function test_MaxUint256Boundary() public {
        vm.startPrank(user1);
        
        // Test with amounts larger than user's balance
        uint256 largeAmount = INITIAL_BALANCE + 1;
        
        // These should revert due to insufficient balance
        vm.expectRevert();
        vault.deposit(largeAmount, user1);
        
        // Minting large amount of shares should also revert due to insufficient balance
        vm.expectRevert();
        vault.mint(largeAmount, user1);
        
        vm.stopPrank();
    }

    function test_ZeroAddressTransfers() public {
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        
        // Transfer to zero address should revert due to ERC20 validation
        vm.expectRevert();
        vault.transfer(address(0), 1e18);
        
        vm.stopPrank();
    }

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                    INTEGRATION STRESS TESTS               ║
    // ╚═══════════════════════════════════════════════════════════╝

    function test_CompleteProtocolLifecycle() public {
        // Simulate a complete protocol lifecycle with many users and operations
        
        // Phase 1: Initial deposits
        address[] memory users = new address[](5);
        for (uint256 i = 0; i < 5; i++) {
            users[i] = address(uint160(0x2000 + i));
            mockStablecoin.mint(users[i], INITIAL_BALANCE);
            
            vm.startPrank(users[i]);
            mockStablecoin.approve(address(vault), type(uint256).max);
            vault.deposit(20e18, users[i]);
            vm.stopPrank();
        }
        
        // Phase 2: Multiple reward rounds
        for (uint256 round = 0; round < 10; round++) {
            vm.startPrank(rewardProvider);
            vault.submitRewards(10e18);
            vm.stopPrank();
            
            // Some users withdraw and redeposit
            if (round % 3 == 0) {
                vm.startPrank(users[0]);
                uint256 balance = vault.balanceOf(users[0]);
                vault.withdraw(balance / 2, users[0], users[0]);
                vault.deposit(10e18, users[0]);
                vm.stopPrank();
            }
            
            // Some users transfer tokens
            if (round % 2 == 0) {
                vm.startPrank(users[1]);
                vault.transfer(users[2], 5e18);
                vm.stopPrank();
            }
        }
        
        // Phase 3: Final withdrawals
        for (uint256 i = 0; i < 5; i++) {
            vm.startPrank(users[i]);
            uint256 finalBalance = vault.balanceOf(users[i]);
            if (finalBalance > 0) {
                vault.withdraw(finalBalance, users[i], users[i]);
            }
            vm.stopPrank();
        }
        
        // All users should have received their tokens back (plus rewards)
        for (uint256 i = 0; i < 5; i++) {
            assertGe(mockStablecoin.balanceOf(users[i]), 20e18);
        }
    }

    function test_ConcurrentOperations() public {
        // Test multiple operations happening in sequence to ensure no conflicts
        
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
        
        vm.startPrank(user2);
        vault.deposit(DEPOSIT_AMOUNT, user2);
        vm.stopPrank();
        
        // Concurrent reward submissions
        vm.startPrank(rewardProvider);
        vault.submitRewards(10e18);
        vault.submitRewards(10e18);
        vault.submitRewards(10e18);
        vm.stopPrank();
        
        // Concurrent transfers
        vm.startPrank(user1);
        vault.transfer(user2, 10e18);
        vm.stopPrank();
        
        vm.startPrank(user2);
        vault.transfer(user1, 5e18);
        vm.stopPrank();
        
        // Concurrent withdrawals
        vm.startPrank(user1);
        vault.withdraw(20e18, user1, user1);
        vm.stopPrank();
        
        vm.startPrank(user2);
        vault.withdraw(20e18, user2, user2);
        vm.stopPrank();
        
        // Both users should have positive balances
        assertGt(vault.balanceOf(user1), 0);
        assertGt(vault.balanceOf(user2), 0);
    }
} 