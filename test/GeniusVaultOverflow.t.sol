// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IAllowanceTransfer} from "permit2/interfaces/IAllowanceTransfer.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {IGeniusVault} from "../src/interfaces/IGeniusVault.sol";
import {GeniusVault} from "../src/GeniusVault.sol";
import {GeniusErrors} from "../src/libs/GeniusErrors.sol";
import {GeniusProxyCall} from "../src/GeniusProxyCall.sol";

import {MockERC20} from "./mocks/MockERC20.sol";
import {MockV3Aggregator} from "./mocks/MockV3Aggregator.sol";

contract GeniusVaultOverflowTest is Test {
    int256 public constant INITIAL_STABLECOIN_PRICE = 100_000_000;
    MockV3Aggregator public MOCK_PRICE_FEED;
    
    uint256 public constant MAX_UINT = type(uint256).max;
    uint256 destChainId = 42;
    
    address OWNER;
    address TRADER;
    uint256 TRADER_PK;
    address ORCHESTRATOR;
    uint256 ORCHESTRATOR_PK;
    bytes32 RECEIVER;

    MockERC20 public USDC_6;  // 6 decimals
    MockERC20 public USDC_18; // 18 decimals
    
    GeniusVault public VAULT;
    GeniusProxyCall public PROXYCALL;
    
    IGeniusVault.Order public order;

    function setUp() public {
        OWNER = makeAddr("OWNER");
        (TRADER, TRADER_PK) = makeAddrAndKey("TRADER");
        RECEIVER = bytes32(uint256(uint160(TRADER)));
        (ORCHESTRATOR, ORCHESTRATOR_PK) = makeAddrAndKey("ORCHESTRATOR");

        MOCK_PRICE_FEED = new MockV3Aggregator(INITIAL_STABLECOIN_PRICE);
        
        // Deploy mock tokens with different decimals
        USDC_6 = new MockERC20("USDC 6 Dec", "USDC6", 6);
        USDC_18 = new MockERC20("USDC 18 Dec", "USDC18", 18);

        PROXYCALL = new GeniusProxyCall(OWNER, new address[](0));

        vm.startPrank(OWNER);

        GeniusVault implementation = new GeniusVault();
        
        bytes memory data = abi.encodeWithSelector(
            GeniusVault.initialize.selector,
            address(USDC_6),
            OWNER,
            address(PROXYCALL),
            7_500,
            address(MOCK_PRICE_FEED),
            86_000,
            98_000_000,
            102_000_000,
            MAX_UINT
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);
        VAULT = GeniusVault(address(proxy));
        
        PROXYCALL.grantRole(PROXYCALL.CALLER_ROLE(), address(VAULT));
        
        VAULT.grantRole(VAULT.ORCHESTRATOR_ROLE(), ORCHESTRATOR);
        VAULT.setTargetChainMinFee(address(USDC_6), destChainId, 1 ether);
        VAULT.setChainStablecoinDecimals(destChainId, 18); // Set destination chain to 18 decimals

        vm.stopPrank();
    }

    function testOverflowOnMaxValue() public {
        // Test with maximum uint256 value
        uint256 maxAmount = type(uint256).max;
        
        vm.startPrank(ORCHESTRATOR);
        order = IGeniusVault.Order({
            seed: keccak256("max_value_order"),
            amountIn: maxAmount,
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            srcChainId: 42,
            destChainId: uint16(block.chainid),
            tokenIn: VAULT.addressToBytes32(address(USDC_18)),
            fee: 1 ether,
            minAmountOut: 0,
            tokenOut: VAULT.addressToBytes32(address(USDC_6))
        });

        deal(address(USDC_18), address(VAULT), maxAmount);
        
        // Should revert due to overflow in decimal conversion
        vm.expectRevert(
            abi.encodeWithSelector(GeniusErrors.InvalidAmount.selector)
        );
        VAULT.fillOrder(order, address(0), "", address(0), "");
    }

    function testDustAmountLoss() public {
        // Test with very small amount that would be lost in conversion
        uint256 dustAmount = 100; // 0.0000000000000001 tokens (18 decimals)
        
        vm.startPrank(ORCHESTRATOR);
        order = IGeniusVault.Order({
            seed: keccak256("dust_amount_order"),
            amountIn: dustAmount,
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            srcChainId: 42,
            destChainId: uint16(block.chainid),
            tokenIn: VAULT.addressToBytes32(address(USDC_18)),
            fee: 0,
            minAmountOut: 0,
            tokenOut: VAULT.addressToBytes32(address(USDC_6))
        });

        deal(address(USDC_18), address(VAULT), dustAmount);
        
        // Should revert due to dust amount being converted to 0
        vm.expectRevert(
            abi.encodeWithSelector(GeniusErrors.InvalidAmount.selector)
        );
        VAULT.fillOrder(order, address(0), "", address(0), "");
    }

    function testRevertOrderDecimalOverflow() public {
        uint256 largeAmount = type(uint256).max / 2;
        
        order = IGeniusVault.Order({
            seed: keccak256("revert_overflow_order"),
            amountIn: largeAmount,
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            srcChainId: block.chainid,
            destChainId: destChainId,
            tokenIn: VAULT.addressToBytes32(address(USDC_6)),
            fee: 1 ether,
            minAmountOut: 0,
            tokenOut: VAULT.addressToBytes32(address(USDC_18))
        });

        // Setup preconditions
        vm.startPrank(TRADER);
        USDC_6.approve(address(VAULT), largeAmount);
        deal(address(USDC_6), TRADER, largeAmount);
        VAULT.createOrder(order);
        vm.stopPrank();

        vm.startPrank(ORCHESTRATOR);
        
        // Generate valid signature
        bytes32 orderHash = VAULT.orderHash(order);
        bytes32 revertDigest = _revertOrderDigest(orderHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ORCHESTRATOR_PK, revertDigest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Ensure vault has enough balance
        deal(address(USDC_6), address(VAULT), largeAmount);
        
        // Should revert due to overflow in decimal conversion
        vm.expectRevert(
            abi.encodeWithSelector(GeniusErrors.InvalidAmount.selector)
        );
        VAULT.revertOrder(order, signature);
    }

    function testPrecisionLossMultiConversion() public {
        // Test precision loss in multiple conversions
        uint256 smallAmount = 1; // 0.000001 in 6 decimals
        
        order = IGeniusVault.Order({
            seed: keccak256("precision_loss_order"),
            amountIn: smallAmount,
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            srcChainId: block.chainid,
            destChainId: destChainId,
            tokenIn: VAULT.addressToBytes32(address(USDC_6)),
            fee: 0,
            minAmountOut: 0,
            tokenOut: VAULT.addressToBytes32(address(USDC_18))
        });

        // Setup
        vm.startPrank(TRADER);
        USDC_6.approve(address(VAULT), smallAmount);
        deal(address(USDC_6), TRADER, smallAmount);
        VAULT.createOrder(order);
        vm.stopPrank();

        vm.startPrank(ORCHESTRATOR);
        
        bytes32 orderHash = VAULT.orderHash(order);
        bytes32 revertDigest = _revertOrderDigest(orderHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ORCHESTRATOR_PK, revertDigest);
        bytes memory signature = abi.encodePacked(r, s, v);

        deal(address(USDC_6), address(VAULT), smallAmount);
        
        // Should revert due to amount being too small after conversion
        vm.expectRevert(
            abi.encodeWithSelector(GeniusErrors.InvalidAmount.selector)
        );
        VAULT.revertOrder(order, signature);
    }

    function _revertOrderDigest(bytes32 _orderHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("PREFIX_CANCEL_ORDER_HASH", _orderHash));
    }
}