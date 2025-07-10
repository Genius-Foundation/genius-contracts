// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MockUSDC} from "./mocks/mockUSDC.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {GeniusVault} from "../src/GeniusVault.sol";
import {GeniusErrors} from "../src/libs/GeniusErrors.sol";
import {GeniusProxyCall} from "../src/GeniusProxyCall.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockV3Aggregator} from "./mocks/MockV3Aggregator.sol";

contract GeniusVaultStakingTest is Test {
    int256 public constant INITIAL_STABLECOIN_PRICE = 100_000_000;
    MockV3Aggregator public MOCK_PRICE_FEED;
    address public permit2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address public owner = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;
    address public trader;

    MockUSDC public usdc;
    GeniusVault public geniusVault;
    GeniusProxyCall public PROXYCALL;

    function setUp() public {
        trader = makeAddr("trader");
        usdc = new MockUSDC();

        PROXYCALL = new GeniusProxyCall(owner, new address[](0));
        MOCK_PRICE_FEED = new MockV3Aggregator(INITIAL_STABLECOIN_PRICE);

        vm.startPrank(owner);
        GeniusVault implementation = new GeniusVault();

        bytes memory data = abi.encodeWithSelector(
            GeniusVault.initialize.selector,
            address(usdc),
            owner,
            address(PROXYCALL),
            7_500,
            address(MOCK_PRICE_FEED),
            86_000,
            99_000_000,
            101_000_000,
            1000 ether
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);

        geniusVault = GeniusVault(address(proxy));

        PROXYCALL.grantRole(PROXYCALL.CALLER_ROLE(), address(geniusVault));

        usdc.mint(trader, 1_000 ether);
        vm.stopPrank();
    }

    function testSelfDeposit() public {
        usdc.approve(address(geniusVault), 1_000 ether);
        uint256 initialContractBalance = usdc.balanceOf(address(this));
        geniusVault.deposit(1_000 ether, address(this));

        assertEq(
            usdc.balanceOf(address(this)),
            initialContractBalance - 1_000 ether,
            "Contract balance should be 999,000 ether"
        );
        assertEq(
            usdc.balanceOf(address(geniusVault)),
            1_000 ether,
            "GeniusVault balance should be 1,000 ether"
        );

        assertEq(
            geniusVault.totalStakedAssets(),
            1_000 ether,
            "Total staked assets should be 1,000 ether"
        );
        assertEq(
            geniusVault.availableAssets(),
            750 ether,
            "Available assets should be 750 ether"
        );
        assertEq(
            geniusVault.balanceOf(address(this)),
            1_000 ether,
            "User shares should be 1,000,000,000"
        );
    }

    function testDepositOnBehalfOf() public {
        uint256 usdcBalance = usdc.balanceOf(trader);
        uint256 geniusVaultBalance = usdc.balanceOf(address(geniusVault));

        assertEq(
            usdcBalance,
            1_000 ether,
            "Trader should initially have 1,000 USDC"
        );
        assertEq(
            geniusVaultBalance,
            0,
            "GeniusVault should initially have 0 USDC"
        );

        // Approve
        vm.prank(trader);
        usdc.approve(address(geniusVault), 1_000 ether);

        // Deposit
        vm.prank(trader);
        geniusVault.deposit(1_000 ether, trader);

        uint256 traderUSDCBalanceAfter = usdc.balanceOf(trader);

        assertEq(
            traderUSDCBalanceAfter,
            0,
            "Trader's USDC balance should be 0 after deposit"
        );
        assertEq(
            usdc.balanceOf(address(geniusVault)),
            1_000 ether,
            "GeniusVault should have 1,000 USDC after deposit"
        );

        assertEq(
            geniusVault.totalStakedAssets(),
            1_000 ether,
            "Total staked assets in GeniusVault should be 1,000 USDC"
        );
        assertEq(
            geniusVault.availableAssets(),
            750 ether,
            "Available assets in GeniusVault should be 100 USDC, reflecting rebalance threshold"
        );
        assertEq(
            geniusVault.balanceOf(trader),
            1_000 ether,
            "Trader should hold shares equivalent to the USDC deposited in GeniusVault"
        );
    }

    function testSelfDepositAndWithdraw() public {
        uint256 usdcBalance = usdc.balanceOf(address(this));

        // Approve the GeniusVault to manage USDC on behalf of the contract
        usdc.approve(address(geniusVault), 1_000 ether);
        geniusVault.deposit(1_000 ether, address(this));
        geniusVault.approve(address(this), 1_000 ether);
        geniusVault.redeem(1_000 ether, address(this), address(this));

        assertEq(
            usdc.balanceOf(address(this)),
            usdcBalance,
            "Contract's USDC should return to initial balance after withdrawal"
        );
        assertEq(
            geniusVault.totalStakedAssets(),
            0,
            "Total assets in the GeniusVault should be 0 after withdrawal"
        );
        assertEq(
            geniusVault.availableAssets(),
            0,
            "Available assets in the GeniusVault should be 0 after withdrawal"
        );
    }

    function testDepositAndWithdrawOnBehalfOf() public {
        assertEq(
            usdc.balanceOf(trader),
            1_000 ether,
            "Trader should initially have 1,000 USDC"
        );

        vm.prank(trader);
        usdc.approve(address(geniusVault), 1_000 ether);

        vm.prank(trader);
        geniusVault.deposit(1_000 ether, trader);
        assertEq(
            usdc.balanceOf(trader),
            0,
            "Trader's USDC should be 0 after deposit"
        );
        assertEq(
            usdc.balanceOf(address(geniusVault)),
            1_000 ether,
            "GeniusVault should have 1,000 USDC after deposit"
        );

        vm.prank(trader);
        geniusVault.approve(trader, 1_000 ether);

        // Withdraw the deposited USDC back to the trader
        vm.prank(trader);
        geniusVault.redeem(1_000 ether, trader, trader);

        assertEq(
            usdc.balanceOf(trader),
            1_000 ether,
            "Trader's USDC should return to initial balance after withdrawal"
        );
        assertEq(
            geniusVault.totalStakedAssets(),
            0,
            "Total assets in the GeniusVault should be 0 after withdrawal"
        );
        assertEq(
            geniusVault.availableAssets(),
            0,
            "Available assets in the GeniusVault should be 0 after withdrawal"
        );
    }

    function testRevertDepositWithoutApproval() public {
        vm.prank(trader);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(
                    keccak256(
                        "ERC20InsufficientAllowance(address,uint256,uint256)"
                    )
                ),
                address(geniusVault),
                0,
                1_000 ether
            )
        );
        geniusVault.deposit(1_000 ether, trader);
    }

    function testWithdrawMoreThanDeposited() public {
        // First, approve and deposit some amount
        vm.prank(trader);
        usdc.approve(address(geniusVault), 500 ether);
        vm.prank(trader);
        geniusVault.deposit(500_000_000, trader);

        vm.prank(trader);
        geniusVault.approve(trader, 1_000 ether);
        vm.expectRevert();
        vm.prank(trader);
        geniusVault.redeem(1_000 ether, trader, trader);
    }

    function testStakeDepositConversion() public {
        vm.startPrank(trader);

        // Approve spending
        usdc.approve(address(geniusVault), type(uint256).max);

        // Deposit 100 stablecoin (18 decimals)
        uint256 expectedVaultTokens = 100 * 1e6; // Expected 100 vault tokens (6 decimals)

        geniusVault.deposit(expectedVaultTokens, trader);

        // Verify balances
        assertEq(
            geniusVault.balanceOf(trader),
            expectedVaultTokens,
            "Incorrect vault token balance after deposit"
        );
        assertEq(
            geniusVault.totalStakedAssets(),
            expectedVaultTokens,
            "Incorrect total staked assets"
        );

        vm.stopPrank();
    }

    function testStakeWithdrawConversion() public {
        vm.startPrank(trader);
        uint256 expectedStablecoin = 50 * 1e18; // Expected 50 stablecoin (18 decimals)

        // First deposit
        usdc.approve(address(geniusVault), type(uint256).max);
        geniusVault.deposit(expectedStablecoin, trader);

        // Withdraw half

        uint256 initialStablecoinBalance = usdc.balanceOf(trader);

        geniusVault.redeem(expectedStablecoin, trader, trader);

        assertEq(
            usdc.balanceOf(trader) - initialStablecoinBalance,
            expectedStablecoin,
            "Incorrect stablecoin amount received"
        );

        vm.stopPrank();
    }
    
    function testLargeAmounts() public {
        vm.startPrank(trader);
        usdc.mint(trader, 1_000_000 ether);
        usdc.approve(address(geniusVault), type(uint256).max);

        // Test with 1 million tokens
        uint256 depositAmount = 1_000_000 * 1e18; // 1M tokens (18 decimals)

        geniusVault.deposit(depositAmount, trader);

        assertEq(
            geniusVault.balanceOf(trader),
            depositAmount,
            "Incorrect vault tokens for large deposit"
        );

        // Withdraw full amount
        uint256 initialStablecoinBalance = usdc.balanceOf(trader);
        geniusVault.redeem(depositAmount, trader, trader);

        assertEq(
            usdc.balanceOf(trader) - initialStablecoinBalance,
            depositAmount,
            "Incorrect stablecoin amount for large withdrawal"
        );

        vm.stopPrank();
    }
}
