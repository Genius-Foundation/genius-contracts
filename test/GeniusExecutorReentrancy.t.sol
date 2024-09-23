// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {PermitSignature} from "./utils/SigUtils.sol";

import {GeniusExecutor} from "../src/GeniusExecutor.sol";
import {GeniusVault} from "../src/GeniusVault.sol";
import {GeniusErrors} from "../src/libs/GeniusErrors.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IAllowanceTransfer, IEIP712} from "permit2/interfaces/IAllowanceTransfer.sol";

import {TestERC20} from "./mocks/TestERC20.sol";
import {MockDEXRouter} from "./mocks/MockDEXRouter.sol";
import {MaliciousToken} from "./mocks/MaliciousToken.sol";
import {MockReentrancyAttacker} from "./mocks/MockReentrancyAttacker.sol";

contract GeniusExecutorReentrancy is Test {
    uint256 avalanche;
    string private rpc = vm.envString("AVALANCHE_RPC_URL");
    bytes32 public DOMAIN_SEPERATOR;

    address public OWNER;
    address public ORCHESTRATOR;
    address public trader;
    bytes32 public RECEIVER =
        keccak256("Bh265EkhNxAQA4rS3ey2QT2yJkE8ZS6QqSvrZTMdm8p7");
    uint256 private privateKey;
    uint48 private nonce;

    address public permit2Address = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address public feeCollector = makeAddr("feeCollector");

    TestERC20 public USDC;
    TestERC20 public WETH;

    PermitSignature public sigUtils;
    IEIP712 public permit2;

    GeniusVault public VAULT;
    GeniusExecutor public EXECUTOR;
    MockDEXRouter public DEX_ROUTER;
    MockReentrancyAttacker public ATTACKER;
    MaliciousToken public MALICIOUS_TOKEN;

    function setUp() public {
        avalanche = vm.createFork(rpc);
        vm.selectFork(avalanche);
        assertEq(vm.activeFork(), avalanche);

        OWNER = makeAddr("owner");
        (address traderAddress, uint256 traderKey) = makeAddrAndKey("trader");
        trader = traderAddress;
        privateKey = traderKey;
        ORCHESTRATOR = makeAddr("orchestrator");

        USDC = new TestERC20();
        WETH = new TestERC20();

        permit2 = IEIP712(permit2Address);
        DOMAIN_SEPERATOR = permit2.DOMAIN_SEPARATOR();
        sigUtils = new PermitSignature();

        vm.startPrank(OWNER);
        GeniusVault implementation = new GeniusVault();

        bytes memory data = abi.encodeWithSelector(
            GeniusVault.initialize.selector,
            address(USDC),
            OWNER
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);

        VAULT = GeniusVault(address(proxy));
        EXECUTOR = new GeniusExecutor(
            permit2Address,
            address(VAULT),
            OWNER,
            new address[](0)
        );
        VAULT.setExecutor(address(EXECUTOR));
        EXECUTOR.grantRole(EXECUTOR.ORCHESTRATOR_ROLE(), ORCHESTRATOR);
        DEX_ROUTER = new MockDEXRouter();
        ATTACKER = new MockReentrancyAttacker(payable(EXECUTOR));
        MALICIOUS_TOKEN = new MaliciousToken(address(EXECUTOR));
        vm.stopPrank();

        deal(address(USDC), trader, 100 ether);
        deal(address(WETH), trader, 100 ether);

        vm.startPrank(trader);
        USDC.approve(permit2Address, type(uint256).max);
        WETH.approve(permit2Address, type(uint256).max);
        vm.stopPrank();
    }

    function generatePermitBatchAndSignature(
        address spender,
        address[2] memory tokens,
        uint160[2] memory amounts
    ) internal returns (IAllowanceTransfer.PermitBatch memory, bytes memory) {
        require(
            tokens.length == amounts.length,
            "Tokens and amounts length mismatch"
        );

        IAllowanceTransfer.PermitDetails[]
            memory permitDetails = new IAllowanceTransfer.PermitDetails[](
                tokens.length
            );

        for (uint i = 0; i < tokens.length; i++) {
            permitDetails[i] = IAllowanceTransfer.PermitDetails({
                token: tokens[i],
                amount: amounts[i],
                expiration: 1900000000,
                nonce: nonce
            });
        }

        nonce++;

        IAllowanceTransfer.PermitBatch memory permitBatch = IAllowanceTransfer
            .PermitBatch({
                details: permitDetails,
                spender: spender,
                sigDeadline: 1900000000
            });

        bytes memory signature = sigUtils.getPermitBatchSignature(
            permitBatch,
            privateKey,
            DOMAIN_SEPERATOR
        );

        return (permitBatch, signature);
    }

    function testReentrancyMultiSwapAndDeposit() public {
        uint32 destChainId = 42;
        uint32 fillDeadline = uint32(block.timestamp + 200);

        vm.startPrank(OWNER);
        EXECUTOR.setAllowedTarget(address(DEX_ROUTER), true);
        EXECUTOR.setAllowedTarget(address(ATTACKER), true);
        vm.stopPrank();

        address[] memory targets = new address[](4);
        targets[0] = address(USDC);
        targets[1] = address(WETH);
        targets[2] = address(DEX_ROUTER);
        targets[3] = address(ATTACKER);

        bytes[] memory data = new bytes[](4);
        data[0] = abi.encodeWithSignature(
            "approve(address,uint256)",
            address(DEX_ROUTER),
            10 ether
        );
        data[1] = abi.encodeWithSignature(
            "approve(address,uint256)",
            address(DEX_ROUTER),
            5 ether
        );
        data[2] = abi.encodeWithSignature(
            "swap(address,address,uint256)",
            address(USDC),
            address(WETH),
            10 ether
        );
        data[3] = abi.encodeWithSignature("attack()");

        uint256[] memory values = new uint256[](4);
        values[0] = 0;
        values[1] = 0;
        values[2] = 0;
        values[3] = 0;

        (
            IAllowanceTransfer.PermitBatch memory permitBatch,
            bytes memory signature
        ) = generatePermitBatchAndSignature(
                address(EXECUTOR),
                [address(USDC), address(WETH)],
                [uint160(10 ether), uint160(5 ether)]
            );

        vm.prank(trader);
        vm.expectRevert();
        EXECUTOR.multiSwapAndDeposit(
            keccak256("order"),
            targets,
            data,
            values,
            permitBatch,
            signature,
            trader,
            destChainId,
            fillDeadline,
            1 ether,
            RECEIVER
        );
    }

    function testReentrancyAggregateWithPermit2() public {
        vm.startPrank(OWNER);
        EXECUTOR.setAllowedTarget(address(ATTACKER), true);
        EXECUTOR.setAllowedTarget(address(DEX_ROUTER), true);
        vm.stopPrank();

        address[] memory targets = new address[](4);
        targets[0] = address(USDC);
        targets[1] = address(WETH);
        targets[2] = address(DEX_ROUTER);
        targets[3] = address(ATTACKER);

        bytes[] memory data = new bytes[](4);
        data[0] = abi.encodeWithSignature(
            "approve(address,uint256)",
            address(DEX_ROUTER),
            10 ether
        );
        data[1] = abi.encodeWithSignature(
            "approve(address,uint256)",
            address(DEX_ROUTER),
            5 ether
        );
        data[2] = abi.encodeWithSignature(
            "swap(address,address,uint256)",
            address(USDC),
            address(WETH),
            10 ether
        );
        data[3] = abi.encodeWithSignature("attack()");

        uint256[] memory values = new uint256[](4);
        values[0] = 0;
        values[1] = 0;
        values[2] = 0;
        values[3] = 0;

        (
            IAllowanceTransfer.PermitBatch memory permitBatch,
            bytes memory signature
        ) = generatePermitBatchAndSignature(
                address(EXECUTOR),
                [address(USDC), address(WETH)],
                [uint160(10 ether), uint160(5 ether)]
            );

        vm.startPrank(ORCHESTRATOR);
        vm.expectRevert(
            abi.encodeWithSelector(
                GeniusErrors.ExternalCallFailed.selector,
                address(ATTACKER),
                3
            )
        );
        EXECUTOR.aggregateWithPermit2(
            targets,
            data,
            values,
            permitBatch,
            signature,
            trader
        );
    }

    function testReentrancyAggregate() public {
        vm.startPrank(OWNER);
        EXECUTOR.setAllowedTarget(address(ATTACKER), true);
        vm.stopPrank();

        address[] memory targets = new address[](1);
        targets[0] = address(ATTACKER);

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("attack()");

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        vm.prank(trader);
        vm.expectRevert(
            abi.encodeWithSelector(
                GeniusErrors.ExternalCallFailed.selector,
                address(ATTACKER),
                0
            )
        );
        EXECUTOR.aggregate(targets, data, values);
    }

    function testReentrancyAggregateWithPermit2MaliciousToken() public {
        vm.startPrank(OWNER);
        EXECUTOR.setAllowedTarget(address(ATTACKER), true);
        EXECUTOR.setAllowedTarget(address(MALICIOUS_TOKEN), true);
        EXECUTOR.setAllowedTarget(address(DEX_ROUTER), true);
        vm.stopPrank();

        // Deal 1 ether to the EXECUTOR
        vm.deal(address(EXECUTOR), 1 ether);

        address[] memory targets = new address[](2);
        targets[0] = address(DEX_ROUTER);
        targets[1] = address(MALICIOUS_TOKEN);

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature(
            "swap(address,address,uint256)",
            address(USDC),
            address(MALICIOUS_TOKEN),
            10 ether
        );
        data[1] = abi.encodeWithSignature(
            "transferFrom(address,address,uint256)",
            address(DEX_ROUTER),
            address(EXECUTOR),
            10 ether
        );

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        (
            IAllowanceTransfer.PermitBatch memory permitBatch,
            bytes memory signature
        ) = generatePermitBatchAndSignature(
                address(EXECUTOR),
                [address(USDC), address(MALICIOUS_TOKEN)],
                [uint160(10 ether), uint160(10 ether)]
            );

        uint256 initialExecutorBalance = address(EXECUTOR).balance;

        vm.startPrank(ORCHESTRATOR);
        vm.expectRevert("TRANSFER_FROM_FAILED");
        EXECUTOR.aggregateWithPermit2(
            targets,
            data,
            values,
            permitBatch,
            signature,
            trader
        );

        // Check that the EXECUTOR's ether balance hasn't changed
        assertEq(
            address(EXECUTOR).balance,
            initialExecutorBalance,
            "EXECUTOR's ether balance should not change"
        );

        // Check that the attacker (MALICIOUS_TOKEN deployer) hasn't received any ether
        assertEq(
            MALICIOUS_TOKEN.attacker().balance,
            0,
            "Attacker should not receive any ether"
        );
    }
}
