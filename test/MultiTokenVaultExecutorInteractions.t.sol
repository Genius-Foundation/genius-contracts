// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {PermitSignature} from "./utils/SigUtils.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IAllowanceTransfer, IEIP712} from "permit2/interfaces/IAllowanceTransfer.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {GeniusMultiTokenVault} from "../src/GeniusMultiTokenVault.sol";
import {GeniusExecutor} from "../src/GeniusExecutor.sol";

import {MockERC20} from "./mocks/MockERC20.sol";
import {MockSwapTarget} from "./mocks/MockSwapTarget.sol";

/**
 * @title MultiTokenVaultExecutorInteractions
 * @dev This contract tests the various functions and
 *      interactions between the GeniusMultiTokenVault and the
 *      GeniusExecutor contracts.
 */
contract MultiTokenVaultExecutorInteractions is Test {
    // ============ Network ============
    uint256 avalanche;
    string private rpc = vm.envString("AVALANCHE_RPC_URL");

    uint32 destChainId = 42;

    uint160 depositAmount = 10 ether;

    // ============ Mocks ============
    MockSwapTarget public ROUTER;

    // ============ External Contracts ============
    ERC20 public USDC = ERC20(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E);
    IEIP712 PERMIT2 = IEIP712(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    // ============ Internal Contracts ============
    GeniusMultiTokenVault public MULTI_VAULT;
    GeniusExecutor public EXECUTOR;
    PermitSignature public SIG_UTILS;

    // ============ Constants ============
    bytes32 public DOMAIN_SEPERATOR;
    uint160 AMOUNT = 10 ether;

    // ============ Accounts ============
    address public OWNER;
    address public TRADER;
    address public ORCHESTRATOR;
    address public BRIDGE;
    bytes32 public RECEIVER = keccak256("receiver");

    // ============ Private Key ============
    uint256 P_KEY;

    // ============ Supported Tokens ============
    address public constant NATIVE = address(0);
    ERC20 public TOKEN1;
    ERC20 public TOKEN2;
    ERC20 public TOKEN3;

    // ============ Setup ============
    function setUp() public {
        avalanche = vm.createFork(rpc);
        vm.selectFork(avalanche);
        DOMAIN_SEPERATOR = PERMIT2.DOMAIN_SEPARATOR();
        SIG_UTILS = new PermitSignature();

        // Set up addresses
        OWNER = address(0x1);
        ORCHESTRATOR = address(0x3);
        BRIDGE = address(0x4);

        (address traderAddress, uint256 traderKey) = makeAddrAndKey("trader");
        TRADER = traderAddress;
        P_KEY = traderKey;

        // Deploy mock tokens
        TOKEN1 = new MockERC20("Token1", "TK1", 18);
        TOKEN2 = new MockERC20("Token2", "TK2", 18);
        TOKEN3 = new MockERC20("Token3", "TK3", 18);

        vm.startPrank(OWNER);

        // Deploy contracts
        ROUTER = new MockSwapTarget();

        // Initialize pool with supported tokens
        address[] memory supportedTokens = new address[](4);
        supportedTokens[0] = NATIVE;
        supportedTokens[1] = address(TOKEN1);
        supportedTokens[2] = address(TOKEN2);
        supportedTokens[3] = address(TOKEN3);

        address[] memory routers = new address[](1);
        routers[0] = address(ROUTER);

        address[] memory bridges = new address[](1);
        bridges[0] = BRIDGE;

        GeniusMultiTokenVault implementation = new GeniusMultiTokenVault();

        bytes memory data = abi.encodeWithSelector(
            GeniusMultiTokenVault.initialize.selector,
            address(USDC),
            OWNER,
            supportedTokens
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);

        MULTI_VAULT = GeniusMultiTokenVault(address(proxy));
        EXECUTOR = new GeniusExecutor(
            address(PERMIT2),
            address(MULTI_VAULT),
            OWNER,
            new address[](0)
        );

        MULTI_VAULT.setExecutor(address(EXECUTOR));
        EXECUTOR.setAllowedTarget(address(ROUTER), true);

        // Add Orchestrator
        MULTI_VAULT.grantRole(MULTI_VAULT.ORCHESTRATOR_ROLE(), ORCHESTRATOR);
        EXECUTOR.grantRole(EXECUTOR.ORCHESTRATOR_ROLE(), ORCHESTRATOR);

        vm.stopPrank();

        // Provide tokens to TRADER and ORCHESTRATOR
        deal(address(USDC), TRADER, 1_000 ether);
        deal(address(USDC), ORCHESTRATOR, 1_000 ether);
        deal(address(USDC), address(this), 1_000 ether);
        deal(address(TOKEN1), TRADER, 1_000 ether);
        deal(address(TOKEN2), TRADER, 1_000 ether);
        deal(address(TOKEN3), TRADER, 1_000 ether);
        deal(address(USDC), address(ROUTER), 100 ether);
        deal(TRADER, 1000 ether); // Provide ETH

        // Approve tokens for MULTI_VAULT
        vm.startPrank(TRADER);
        TOKEN1.approve(address(PERMIT2), 1_000 ether);
        TOKEN2.approve(address(PERMIT2), 1_000 ether);

        TOKEN1.approve(address(ROUTER), AMOUNT / 2);
        TOKEN2.approve(address(ROUTER), AMOUNT / 2);
        vm.stopPrank();
    }

    function testTokenSwapAndDeposit() public {
        bytes memory swapCalldata = abi.encodeWithSelector(
            MockSwapTarget.mockSwap.selector,
            address(TOKEN1),
            AMOUNT,
            address(USDC),
            address(EXECUTOR),
            AMOUNT / 2
        );

        // Set up permit details for WAVAX
        IAllowanceTransfer.PermitDetails[]
            memory permitDetails = new IAllowanceTransfer.PermitDetails[](1);
        permitDetails[0] = IAllowanceTransfer.PermitDetails({
            token: address(TOKEN1),
            amount: AMOUNT,
            expiration: 1900000000,
            nonce: 0
        });

        IAllowanceTransfer.PermitBatch memory permitBatch = IAllowanceTransfer
            .PermitBatch({
                details: permitDetails,
                spender: address(EXECUTOR),
                sigDeadline: 1900000000
            });

        bytes memory permitSignature = SIG_UTILS.getPermitBatchSignature(
            permitBatch,
            P_KEY,
            DOMAIN_SEPERATOR
        );

        bytes32 hashedParams = keccak256(
            abi.encode(
                keccak256("order"),
                address(ROUTER),
                swapCalldata,
                permitBatch,
                permitSignature,
                TRADER,
                destChainId,
                uint32(block.timestamp + 200),
                1 ether,
                RECEIVER,
                0,
                bytes32(uint256(1)),
                EXECUTOR.getNonce(address(TRADER)),
                address(EXECUTOR)
            )
        );

        bytes memory signature = _hashToSignature(hashedParams);

        // Perform the swap and deposit via GeniusExecutor
        vm.prank(ORCHESTRATOR);
        EXECUTOR.tokenSwapAndDeposit(
            keccak256("order"),
            address(ROUTER),
            swapCalldata,
            permitBatch,
            permitSignature,
            TRADER,
            destChainId,
            uint32(block.timestamp + 200),
            1 ether,
            RECEIVER,
            0,
            bytes32(uint256(1)),
            signature
        );

        assertEq(
            USDC.balanceOf(address(EXECUTOR)),
            0,
            "EXECUTOR should have 0 test tokens"
        );
        assertEq(
            USDC.balanceOf(address(MULTI_VAULT)),
            5 ether,
            "MULTI_VAULT should have 5 test tokens"
        );
        assertEq(
            MULTI_VAULT.stablecoinBalance(),
            5 ether,
            "MULTI_VAULT should have 5 test tokens available"
        );
        assertEq(
            MULTI_VAULT.availableAssets(),
            0 ether,
            "MULTI_VAULT should have 90% of test tokens available"
        );
        assertEq(
            MULTI_VAULT.totalStakedAssets(),
            0,
            "MULTI_VAULT should have 0 test tokens staked"
        );
    }

    function testMultiSwapAndDeposit() public {
        // Set up permit details for WAVAX
        IAllowanceTransfer.PermitDetails[]
            memory permitDetails = new IAllowanceTransfer.PermitDetails[](2);
        permitDetails[0] = IAllowanceTransfer.PermitDetails({
            token: address(TOKEN1),
            amount: AMOUNT,
            expiration: 1900000000,
            nonce: 0
        });

        permitDetails[1] = IAllowanceTransfer.PermitDetails({
            token: address(TOKEN2),
            amount: AMOUNT,
            expiration: 1900000000,
            nonce: 0
        });

        IAllowanceTransfer.PermitBatch memory permitBatch = IAllowanceTransfer
            .PermitBatch({
                details: permitDetails,
                spender: address(EXECUTOR),
                sigDeadline: 1900000000
            });

        bytes memory permitSignature = SIG_UTILS.getPermitBatchSignature(
            permitBatch,
            P_KEY,
            DOMAIN_SEPERATOR
        );

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(
            MockSwapTarget.mockSwap.selector,
            address(TOKEN1),
            AMOUNT,
            address(USDC),
            address(EXECUTOR),
            AMOUNT / 2
        );
        data[1] = abi.encodeWithSelector(
            MockSwapTarget.mockSwap.selector,
            address(TOKEN2),
            AMOUNT,
            address(USDC),
            address(EXECUTOR),
            AMOUNT / 2
        );

        address[] memory targets = new address[](2);
        targets[0] = address(ROUTER);
        targets[1] = address(ROUTER);

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        address[] memory routers = new address[](2);
        routers[0] = address(ROUTER);
        routers[1] = address(ROUTER);

        vm.startPrank(address(EXECUTOR));
        TOKEN1.approve(address(ROUTER), AMOUNT);
        TOKEN2.approve(address(ROUTER), AMOUNT);
        vm.stopPrank();

        bytes32 hashedParams = keccak256(
            abi.encode(
                keccak256("order"),
                targets,
                data,
                values,
                permitBatch,
                permitSignature,
                TRADER,
                42,
                uint32(uint32(block.timestamp + 200)),
                1 ether,
                RECEIVER,
                0,
                bytes32(uint256(1)),
                EXECUTOR.getNonce(address(TRADER)),
                address(EXECUTOR)
            )
        );

        bytes memory signature = _hashToSignature(hashedParams);

        // Perform the swap and deposit via GeniusExecutor
        vm.startPrank(ORCHESTRATOR);
        EXECUTOR.multiSwapAndDeposit(
            keccak256("order"),
            targets,
            data,
            values,
            permitBatch,
            permitSignature,
            TRADER,
            42,
            uint32(uint32(block.timestamp + 200)),
            1 ether,
            RECEIVER,
            0,
            bytes32(uint256(1)),
            signature
        );

        assertEq(
            USDC.balanceOf(address(EXECUTOR)),
            0,
            "EXECUTOR should have 0 test tokens"
        );
        assertEq(
            USDC.balanceOf(address(MULTI_VAULT)),
            10 ether,
            "MULTI_VAULT should have 10 test tokens"
        );
        assertEq(
            MULTI_VAULT.stablecoinBalance(),
            10 ether,
            "MULTI_VAULT should have 10 test tokens available"
        );
        assertEq(
            MULTI_VAULT.availableAssets(),
            0 ether,
            "MULTI_VAULT should have 90% of test tokens available"
        );
        assertEq(
            MULTI_VAULT.totalStakedAssets(),
            0,
            "MULTI_VAULT should have 0 test tokens staked "
        );
    }

    function testNativeSwapAndDeposit() public {
        uint256 swapAmount = 100 ether;

        // Prepare swap calldata
        bytes memory swapCalldata = abi.encodeWithSelector(
            MockSwapTarget.mockSwap.selector,
            NATIVE,
            swapAmount,
            address(USDC),
            address(EXECUTOR),
            50 ether
        );

        // Perform the native swap and deposit via GeniusExecutor
        vm.prank(TRADER);
        EXECUTOR.nativeSwapAndDeposit{value: swapAmount}(
            keccak256("order"),
            address(ROUTER),
            swapCalldata,
            swapAmount,
            destChainId,
            uint32(block.timestamp + 200),
            1 ether,
            RECEIVER,
            0,
            bytes32(uint256(1))
        );

        assertEq(
            USDC.balanceOf(address(EXECUTOR)),
            0,
            "EXECUTOR should have 0 USDC"
        );
        assertEq(
            USDC.balanceOf(address(MULTI_VAULT)),
            50 ether,
            "MULTI_VAULT should have 5 USDC"
        );
        assertEq(
            MULTI_VAULT.stablecoinBalance(),
            50 ether,
            "MULTI_VAULT should have 5 USDC available"
        );
        assertEq(
            MULTI_VAULT.availableAssets(),
            0 ether,
            "MULTI_VAULT should have 90% of USDC available"
        );
        assertEq(
            MULTI_VAULT.totalStakedAssets(),
            0,
            "MULTI_VAULT should have 0 USDC staked"
        );
        assertEq(TRADER.balance, 900 ether, "TRADER should have 0 ETH");
    }

    function testDepositToVault() public {
        // Set up initial balances
        deal(address(USDC), TRADER, 100 ether);

        vm.startPrank(TRADER);
        USDC.approve(address(PERMIT2), 100 ether);
        USDC.approve(address(EXECUTOR), 100 ether);
        vm.stopPrank();

        // Set up permit details for USDC
        IAllowanceTransfer.PermitDetails[]
            memory permitDetails = new IAllowanceTransfer.PermitDetails[](1);
        permitDetails[0] = IAllowanceTransfer.PermitDetails({
            token: address(USDC),
            amount: depositAmount,
            expiration: 1900000000,
            nonce: 0
        });

        IAllowanceTransfer.PermitBatch memory permitBatch = IAllowanceTransfer
            .PermitBatch({
                details: permitDetails,
                spender: address(EXECUTOR),
                sigDeadline: 1900000000
            });

        bytes memory signature = SIG_UTILS.getPermitBatchSignature(
            permitBatch,
            P_KEY,
            DOMAIN_SEPERATOR
        );

        // Perform the deposit via GeniusExecutor
        vm.prank(ORCHESTRATOR);
        EXECUTOR.depositToVault(permitBatch, signature, TRADER);

        assertEq(
            USDC.balanceOf(address(EXECUTOR)),
            0,
            "EXECUTOR should have 0 USDC"
        );
        assertEq(
            MULTI_VAULT.totalStakedAssets(),
            depositAmount,
            "VAULT should have 10 USDC"
        );
        assertEq(
            MULTI_VAULT.balanceOf(TRADER),
            depositAmount,
            "TRADER should have 10 vault shares"
        );
        assertEq(
            USDC.balanceOf(TRADER),
            90 ether,
            "TRADER should have 90 USDC"
        );
    }

    function testWithdrawFromVault() public {
        uint160 withdrawAmount = 1 ether;

        vm.startPrank(TRADER);
        USDC.approve(address(MULTI_VAULT), 100 ether);
        USDC.approve(address(PERMIT2), 100 ether);
        USDC.approve(address(EXECUTOR), 100 ether);
        MULTI_VAULT.approve(address(PERMIT2), 100 ether);
        vm.stopPrank();

        // Set up permit details for deposit
        IAllowanceTransfer.PermitDetails[]
            memory depositPermitDetails = new IAllowanceTransfer.PermitDetails[](
                1
            );
        depositPermitDetails[0] = IAllowanceTransfer.PermitDetails({
            token: address(USDC),
            amount: depositAmount,
            expiration: 1900000000,
            nonce: 0
        });

        IAllowanceTransfer.PermitBatch
            memory depositPermitBatch = IAllowanceTransfer.PermitBatch({
                details: depositPermitDetails,
                spender: address(EXECUTOR),
                sigDeadline: 1900000000
            });

        bytes memory depositSignature = SIG_UTILS.getPermitBatchSignature(
            depositPermitBatch,
            P_KEY,
            DOMAIN_SEPERATOR
        );

        // Perform the deposit
        vm.startPrank(ORCHESTRATOR);
        console.log("msg.sender", msg.sender);
        EXECUTOR.depositToVault(depositPermitBatch, depositSignature, TRADER);
        console.log("deposit successful");
        vm.startPrank(TRADER);
        MULTI_VAULT.approve(address(EXECUTOR), MULTI_VAULT.balanceOf(TRADER));
        vm.stopPrank();

        // Now set up the withdrawal
        // Set up permit details for withdrawal (vault shares)
        IAllowanceTransfer.PermitDetails[]
            memory withdrawPermitDetails = new IAllowanceTransfer.PermitDetails[](
                1
            );
        withdrawPermitDetails[0] = IAllowanceTransfer.PermitDetails({
            token: address(MULTI_VAULT),
            amount: withdrawAmount,
            expiration: 1900000000,
            nonce: 0
        });

        IAllowanceTransfer.PermitBatch
            memory withdrawPermitBatch = IAllowanceTransfer.PermitBatch({
                details: withdrawPermitDetails,
                spender: address(EXECUTOR),
                sigDeadline: 1900000000
            });

        bytes memory withdrawSignature = SIG_UTILS.getPermitBatchSignature(
            withdrawPermitBatch,
            P_KEY,
            DOMAIN_SEPERATOR
        );
        vm.stopPrank();

        vm.startPrank(ORCHESTRATOR);
        // Perform the withdrawal via GeniusExecutor
        EXECUTOR.withdrawFromVault(
            withdrawPermitBatch,
            withdrawSignature,
            TRADER
        );
        vm.stopPrank();

        assertEq(
            USDC.balanceOf(address(EXECUTOR)),
            0,
            "EXECUTOR should have 0 USDC"
        );
        assertEq(
            USDC.balanceOf(address(MULTI_VAULT)),
            9 ether,
            "MULTI_VAULT should have 9 USDC"
        );
        assertEq(
            MULTI_VAULT.totalStakedAssets(),
            9 ether,
            "VAULT should have 9 USDC"
        );
        assertEq(
            MULTI_VAULT.balanceOf(TRADER),
            9 ether,
            "TRADER should have 9 vault shares"
        );
        assertEq(
            USDC.balanceOf(TRADER),
            991 ether,
            "TRADER should have 991 USDC"
        );
    }

    function _hashToSignature(
        bytes32 hashedValues
    ) internal view returns (bytes memory) {
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", hashedValues)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(P_KEY, ethSignedMessageHash);
        return abi.encodePacked(r, s, v);
    }
}
