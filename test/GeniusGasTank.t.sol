// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import {Test} from "forge-std/Test.sol";
import {GeniusProxyCall} from "../src/GeniusProxyCall.sol";
import {GeniusGasTank} from "../src/GeniusGasTank.sol";
import {MockDEXRouter} from "./mocks/MockDEXRouter.sol";
import {IAllowanceTransfer} from "permit2/interfaces/IAllowanceTransfer.sol";
import {PermitSignature} from "./utils/SigUtils.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IEIP712} from "permit2/interfaces/IEIP712.sol";
import {GeniusErrors} from "../src/libs/GeniusErrors.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract GeniusGasTankTest is Test {
    uint256 constant BASE_USER_USDC_BALANCE = 100 ether;
    uint256 constant BASE_USER_DAI_BALANCE = 100 ether;
    uint256 constant BASE_ROUTER_WETH_BALANCE = 100 ether;

    bytes32 public DOMAIN_SEPERATOR;

    uint256 avalanche;
    string private rpc = vm.envString("AVALANCHE_RPC_URL");

    IEIP712 public PERMIT2;
    PermitSignature public sigUtils;

    GeniusProxyCall public PROXYCALL;
    GeniusGasTank public GAS_TANK;
    ERC20 public USDC;
    ERC20 public WETH;
    ERC20 public DAI;

    MockDEXRouter ROUTER;
    address ADMIN = makeAddr("ADMIN");
    address SENDER = makeAddr("SENDER");
    address FEE_RECIPIENT = makeAddr("FEE_RECIPIENT");

    address USER;
    uint256 USER_PK;

    function setUp() public {
        avalanche = vm.createFork(rpc);

        vm.selectFork(avalanche);
        assertEq(vm.activeFork(), avalanche);

        (USER, USER_PK) = makeAddrAndKey("user");

        ROUTER = new MockDEXRouter();
        PERMIT2 = IEIP712(0x000000000022D473030F116dDEE9F6B43aC78BA3);
        DOMAIN_SEPERATOR = PERMIT2.DOMAIN_SEPARATOR();

        PROXYCALL = new GeniusProxyCall(ADMIN, new address[](0));
        USDC = ERC20(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E);
        WETH = ERC20(0x49D5c2BdFfac6CE2BFdB6640F4F80f226bc10bAB);
        DAI = ERC20(0xd586E7F844cEa2F87f50152665BCbc2C279D8d70);
        sigUtils = new PermitSignature();

        address[] memory allowedTargets = new address[](1);
        allowedTargets[0] = address(ROUTER);

        GAS_TANK = new GeniusGasTank(
            ADMIN,
            payable(FEE_RECIPIENT),
            address(PERMIT2),
            address(PROXYCALL)
        );

        vm.startPrank(ADMIN);
        PROXYCALL.grantRole(PROXYCALL.CALLER_ROLE(), address(GAS_TANK));
        vm.stopPrank();

        deal(address(USDC), USER, BASE_USER_USDC_BALANCE);
        deal(address(DAI), USER, BASE_USER_DAI_BALANCE);
        deal(address(WETH), address(ROUTER), BASE_ROUTER_WETH_BALANCE);

        vm.startPrank(USER);
        USDC.approve(address(PERMIT2), type(uint256).max);
        DAI.approve(address(PERMIT2), type(uint256).max);
        vm.stopPrank();
    }

    function testSponsorTokenNonAllowedTarget() public {
        IAllowanceTransfer.PermitDetails memory details = IAllowanceTransfer
            .PermitDetails({
                token: address(USDC),
                amount: uint160(BASE_USER_USDC_BALANCE),
                nonce: 0,
                expiration: 1900000000
            });

        IAllowanceTransfer.PermitDetails[]
            memory detailsArray = new IAllowanceTransfer.PermitDetails[](1);

        detailsArray[0] = details;

        (
            IAllowanceTransfer.PermitBatch memory permitBatch,
            bytes memory permitSignature
        ) = _generatePermitBatchSignature(detailsArray);

        bytes memory data = abi.encodeWithSignature(
            "transfer(address,uint256)",
            address(ROUTER),
            BASE_USER_USDC_BALANCE
        );

        bytes memory sponsorSignature = _generateSignature(
            address(USDC),
            data,
            permitBatch,
            GAS_TANK.nonces(USER),
            address(USDC),
            0,
            1900000000,
            USER_PK
        );

        vm.startPrank(SENDER);

        GAS_TANK.sponsorOrderedTransactions(
            address(USDC),
            data,
            permitBatch,
            permitSignature,
            USER,
            address(USDC),
            0,
            1900000000,
            sponsorSignature
        );

        assertEq(
            USDC.balanceOf(address(ROUTER)),
            BASE_USER_USDC_BALANCE,
            "USDC balance mismatch"
        );

        vm.stopPrank();
    }

    function testSponsorSwap() public {
        IAllowanceTransfer.PermitDetails memory details = IAllowanceTransfer
            .PermitDetails({
                token: address(USDC),
                amount: uint160(BASE_USER_USDC_BALANCE),
                nonce: 0,
                expiration: 1900000000
            });

        IAllowanceTransfer.PermitDetails[]
            memory detailsArray = new IAllowanceTransfer.PermitDetails[](1);

        detailsArray[0] = details;

        (
            IAllowanceTransfer.PermitBatch memory permitBatch,
            bytes memory permitSignature
        ) = _generatePermitBatchSignature(detailsArray);

        bytes memory data = abi.encodeWithSignature(
            "swapTo(address,address,uint256,address)",
            address(USDC),
            address(WETH),
            BASE_USER_USDC_BALANCE,
            USER
        );

        bytes memory sponsorSignature = _generateSignature(
            address(ROUTER),
            data,
            permitBatch,
            GAS_TANK.nonces(USER),
            address(USDC),
            0,
            1900000000,
            USER_PK
        );

        vm.startPrank(SENDER);

        GAS_TANK.sponsorOrderedTransactions(
            address(ROUTER),
            data,
            permitBatch,
            permitSignature,
            USER,
            address(USDC),
            0,
            1900000000,
            sponsorSignature
        );

        assertEq(
            USDC.balanceOf(address(ROUTER)),
            BASE_USER_USDC_BALANCE,
            "USDC balance mismatch"
        );
        assertEq(
            WETH.balanceOf(address(ROUTER)),
            BASE_ROUTER_WETH_BALANCE / 2,
            "WETH balance mismatch"
        );

        assertEq(USDC.balanceOf(USER), 0, "USDC balance mismatch");
        assertEq(
            WETH.balanceOf(USER),
            BASE_ROUTER_WETH_BALANCE / 2,
            "WETH balance mismatch"
        );

        vm.stopPrank();
    }

    function testSponsorSwapWithFees() public {
        IAllowanceTransfer.PermitDetails memory details = IAllowanceTransfer
            .PermitDetails({
                token: address(USDC),
                amount: uint160(BASE_USER_USDC_BALANCE),
                nonce: 0,
                expiration: 1900000000
            });

        IAllowanceTransfer.PermitDetails[]
            memory detailsArray = new IAllowanceTransfer.PermitDetails[](1);

        detailsArray[0] = details;

        (
            IAllowanceTransfer.PermitBatch memory permitBatch,
            bytes memory permitSignature
        ) = _generatePermitBatchSignature(detailsArray);

        bytes memory data = abi.encodeWithSignature(
            "swapTo(address,address,uint256,address)",
            address(USDC),
            address(WETH),
            BASE_USER_USDC_BALANCE - 1 ether,
            USER
        );

        bytes memory sponsorSignature = _generateSignature(
            address(ROUTER),
            data,
            permitBatch,
            GAS_TANK.nonces(USER),
            address(USDC),
            1 ether,
            1900000000,
            USER_PK
        );

        vm.startPrank(SENDER);

        GAS_TANK.sponsorOrderedTransactions(
            address(ROUTER),
            data,
            permitBatch,
            permitSignature,
            USER,
            address(USDC),
            1 ether,
            1900000000,
            sponsorSignature
        );

        assertEq(
            USDC.balanceOf(address(ROUTER)),
            BASE_USER_USDC_BALANCE - 1 ether,
            "USDC balance mismatch"
        );

        assertEq(
            USDC.balanceOf(FEE_RECIPIENT),
            1 ether,
            "Fee not transferred correctly"
        );

        assertEq(
            WETH.balanceOf(address(ROUTER)),
            BASE_ROUTER_WETH_BALANCE / 2,
            "WETH balance mismatch"
        );

        assertEq(USDC.balanceOf(USER), 0, "USDC balance mismatch");
        assertEq(
            WETH.balanceOf(USER),
            BASE_ROUTER_WETH_BALANCE / 2,
            "WETH balance mismatch"
        );

        vm.stopPrank();
    }

    function testSponsorSwapWithFee() public {
        IAllowanceTransfer.PermitDetails memory details = IAllowanceTransfer
            .PermitDetails({
                token: address(USDC),
                amount: uint160(BASE_USER_USDC_BALANCE),
                nonce: 0,
                expiration: 1900000000
            });

        IAllowanceTransfer.PermitDetails[]
            memory detailsArray = new IAllowanceTransfer.PermitDetails[](1);

        detailsArray[0] = details;

        (
            IAllowanceTransfer.PermitBatch memory permitBatch,
            bytes memory permitSignature
        ) = _generatePermitBatchSignature(detailsArray);

        address target = address(ROUTER);
        bytes memory data = abi.encodeWithSignature(
            "swapTo(address,address,uint256,address)",
            address(USDC),
            address(WETH),
            BASE_USER_USDC_BALANCE - 1 ether,
            USER
        );

        uint256 feeAmount = 1 ether;

        bytes memory sponsorSignature = _generateSignature(
            target,
            data,
            permitBatch,
            GAS_TANK.nonces(USER),
            address(USDC),
            feeAmount,
            1900000000,
            USER_PK
        );

        vm.startPrank(SENDER);

        GAS_TANK.sponsorOrderedTransactions(
            target,
            data,
            permitBatch,
            permitSignature,
            USER,
            address(USDC),
            feeAmount,
            1900000000,
            sponsorSignature
        );

        assertEq(
            USDC.balanceOf(FEE_RECIPIENT),
            feeAmount,
            "Fee not transferred correctly"
        );
        assertEq(
            USDC.balanceOf(address(ROUTER)),
            BASE_USER_USDC_BALANCE - feeAmount,
            "USDC balance mismatch"
        );
        assertEq(
            WETH.balanceOf(USER),
            BASE_ROUTER_WETH_BALANCE / 2,
            "WETH balance mismatch"
        );

        vm.stopPrank();
    }

    function testSponsorSwapInvalidSignature() public {
        IAllowanceTransfer.PermitDetails memory details = IAllowanceTransfer
            .PermitDetails({
                token: address(USDC),
                amount: uint160(BASE_USER_USDC_BALANCE),
                nonce: 0,
                expiration: 1900000000
            });

        IAllowanceTransfer.PermitDetails[]
            memory detailsArray = new IAllowanceTransfer.PermitDetails[](1);

        detailsArray[0] = details;

        (
            IAllowanceTransfer.PermitBatch memory permitBatch,
            bytes memory permitSignature
        ) = _generatePermitBatchSignature(detailsArray);

        bytes memory data = abi.encodeWithSignature(
            "swapTo(address,address,uint256,address)",
            address(USDC),
            address(WETH),
            BASE_USER_USDC_BALANCE,
            USER
        );

        bytes memory invalidSignature = abi.encodePacked(
            bytes32(0),
            bytes32(0),
            uint8(0)
        );

        //revert with ECDSAInvalidSignature()
        vm.expectRevert(
            abi.encodeWithSelector(ECDSA.ECDSAInvalidSignature.selector)
        );
        GAS_TANK.sponsorOrderedTransactions(
            address(USDC),
            data,
            permitBatch,
            permitSignature,
            USER,
            address(USDC),
            0,
            1900000000,
            invalidSignature
        );
    }

    function testSponsorSwapExpiredDeadline() public {
        IAllowanceTransfer.PermitDetails memory details = IAllowanceTransfer
            .PermitDetails({
                token: address(USDC),
                amount: uint160(BASE_USER_USDC_BALANCE),
                nonce: 0,
                expiration: 1900000000
            });

        IAllowanceTransfer.PermitDetails[]
            memory detailsArray = new IAllowanceTransfer.PermitDetails[](1);

        detailsArray[0] = details;

        (
            IAllowanceTransfer.PermitBatch memory permitBatch,
            bytes memory permitSignature
        ) = _generatePermitBatchSignature(detailsArray);

        bytes memory data = abi.encodeWithSignature(
            "swapTo(address,address,uint256,address)",
            address(USDC),
            address(WETH),
            BASE_USER_USDC_BALANCE,
            USER
        );

        uint256 expiredDeadline = block.timestamp - 1;

        bytes memory sponsorSignature = _generateSignature(
            address(ROUTER),
            data,
            permitBatch,
            GAS_TANK.nonces(USER),
            address(USDC),
            0,
            expiredDeadline,
            USER_PK
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                GeniusErrors.DeadlinePassed.selector,
                expiredDeadline
            )
        );
        GAS_TANK.sponsorOrderedTransactions(
            address(ROUTER),
            data,
            permitBatch,
            permitSignature,
            USER,
            address(USDC),
            0,
            expiredDeadline,
            sponsorSignature
        );
    }

    function testSponsorSwapMultipleTokens() public {
        IAllowanceTransfer.PermitDetails[]
            memory details = new IAllowanceTransfer.PermitDetails[](2);
        details[0] = IAllowanceTransfer.PermitDetails({
            token: address(USDC),
            amount: uint160(BASE_USER_USDC_BALANCE),
            nonce: 0,
            expiration: 1900000000
        });
        details[1] = IAllowanceTransfer.PermitDetails({
            token: address(DAI),
            amount: uint160(BASE_USER_DAI_BALANCE),
            nonce: 0,
            expiration: 1900000000
        });

        (
            IAllowanceTransfer.PermitBatch memory permitBatch,
            bytes memory permitSignature
        ) = _generatePermitBatchSignature(details);

        address[] memory targets = new address[](4);
        bytes[] memory data = new bytes[](4);
        uint256[] memory values = new uint256[](4);

        targets[0] = address(USDC);
        data[0] = abi.encodeWithSignature(
            "approve(address,uint256)",
            address(ROUTER),
            BASE_USER_USDC_BALANCE
        );
        targets[1] = address(DAI);
        data[1] = abi.encodeWithSignature(
            "approve(address,uint256)",
            address(ROUTER),
            BASE_USER_DAI_BALANCE
        );
        targets[2] = address(ROUTER);
        data[2] = abi.encodeWithSignature(
            "swapTo(address,address,uint256,address)",
            address(USDC),
            address(WETH),
            BASE_USER_USDC_BALANCE,
            USER
        );
        targets[3] = address(ROUTER);
        data[3] = abi.encodeWithSignature(
            "swapTo(address,address,uint256,address)",
            address(DAI),
            address(WETH),
            BASE_USER_DAI_BALANCE,
            USER
        );
        values[0] = 0;
        values[1] = 0;
        values[2] = 0;
        values[3] = 0;

        bytes memory transactions = _encodeTransactions(targets, values, data);

        bytes memory sponsorSignature = _generateSignature(
            address(PROXYCALL),
            transactions,
            permitBatch,
            GAS_TANK.nonces(USER),
            address(USDC),
            0,
            1900000000,
            USER_PK
        );

        vm.startPrank(USER);

        GAS_TANK.sponsorOrderedTransactions(
            address(PROXYCALL),
            transactions,
            permitBatch,
            permitSignature,
            USER,
            address(USDC),
            0,
            1900000000,
            sponsorSignature
        );

        assertEq(USDC.balanceOf(USER), 0, "USDC balance mismatch");
        assertEq(DAI.balanceOf(USER), 0, "DAI balance mismatch");
        assertEq(
            WETH.balanceOf(USER),
            (BASE_ROUTER_WETH_BALANCE * 75) / 100,
            "WETH balance mismatch"
        );

        vm.stopPrank();
    }

    function testPauseUnpause() public {
        vm.prank(ADMIN);
        GAS_TANK.pause();

        IAllowanceTransfer.PermitDetails memory details = IAllowanceTransfer
            .PermitDetails({
                token: address(USDC),
                amount: uint160(BASE_USER_USDC_BALANCE),
                nonce: 0,
                expiration: 1900000000
            });

        IAllowanceTransfer.PermitDetails[]
            memory detailsArray = new IAllowanceTransfer.PermitDetails[](1);

        detailsArray[0] = details;

        (
            IAllowanceTransfer.PermitBatch memory permitBatch,
            bytes memory permitSignature
        ) = _generatePermitBatchSignature(detailsArray);

        bytes memory data = abi.encodeWithSignature(
            "swapTo(address,address,uint256,address)",
            address(USDC),
            address(WETH),
            BASE_USER_USDC_BALANCE,
            USER
        );

        bytes memory sponsorSignature = _generateSignature(
            address(ROUTER),
            data,
            permitBatch,
            GAS_TANK.nonces(USER),
            address(USDC),
            0,
            1900000000,
            USER_PK
        );

        vm.expectRevert(
            abi.encodeWithSelector(Pausable.EnforcedPause.selector)
        );
        GAS_TANK.sponsorOrderedTransactions(
            address(ROUTER),
            data,
            permitBatch,
            permitSignature,
            USER,
            address(USDC),
            0,
            1900000000,
            sponsorSignature
        );

        vm.prank(ADMIN);
        GAS_TANK.unpause();

        vm.prank(USER);
        GAS_TANK.sponsorOrderedTransactions(
            address(ROUTER),
            data,
            permitBatch,
            permitSignature,
            USER,
            address(USDC),
            0,
            1900000000,
            sponsorSignature
        );

        assertEq(
            WETH.balanceOf(USER),
            BASE_ROUTER_WETH_BALANCE / 2,
            "WETH balance mismatch after unpause"
        );
    }

    function testSetFeeRecipient() public {
        address newFeeRecipient = makeAddr("NEW_FEE_RECIPIENT");

        vm.prank(ADMIN);
        GAS_TANK.setFeeRecipient(payable(newFeeRecipient));

        IAllowanceTransfer.PermitDetails memory details = IAllowanceTransfer
            .PermitDetails({
                token: address(USDC),
                amount: uint160(BASE_USER_USDC_BALANCE),
                nonce: 0,
                expiration: 1900000000
            });

        IAllowanceTransfer.PermitDetails[]
            memory detailsArray = new IAllowanceTransfer.PermitDetails[](1);

        detailsArray[0] = details;

        (
            IAllowanceTransfer.PermitBatch memory permitBatch,
            bytes memory permitSignature
        ) = _generatePermitBatchSignature(detailsArray);

        bytes memory data = abi.encodeWithSignature(
            "swapTo(address,address,uint256,address)",
            address(USDC),
            address(WETH),
            BASE_USER_USDC_BALANCE - 1 ether,
            USER
        );

        uint256 feeAmount = 1 ether;

        bytes memory sponsorSignature = _generateSignature(
            address(ROUTER),
            data,
            permitBatch,
            GAS_TANK.nonces(USER),
            address(USDC),
            feeAmount,
            1900000000,
            USER_PK
        );

        vm.prank(USER);
        GAS_TANK.sponsorOrderedTransactions(
            address(ROUTER),
            data,
            permitBatch,
            permitSignature,
            USER,
            address(USDC),
            feeAmount,
            1900000000,
            sponsorSignature
        );

        assertEq(
            USDC.balanceOf(newFeeRecipient),
            feeAmount,
            "Fee not transferred to new recipient"
        );
    }

    function testSetFeeRecipientUnauthorized() public {
        address newFeeRecipient = makeAddr("NEW_FEE_RECIPIENT");

        vm.prank(USER);
        vm.expectRevert(GeniusErrors.IsNotAdmin.selector);
        GAS_TANK.setFeeRecipient(payable(newFeeRecipient));
    }

    function testNonceIncrement() public {
        IAllowanceTransfer.PermitDetails memory details = IAllowanceTransfer
            .PermitDetails({
                token: address(USDC),
                amount: uint160(BASE_USER_USDC_BALANCE),
                nonce: 0,
                expiration: 1900000000
            });

        IAllowanceTransfer.PermitDetails[]
            memory detailsArray = new IAllowanceTransfer.PermitDetails[](1);

        detailsArray[0] = details;

        (
            IAllowanceTransfer.PermitBatch memory permitBatch,
            bytes memory permitSignature
        ) = _generatePermitBatchSignature(detailsArray);

        bytes memory data = abi.encodeWithSignature(
            "swapTo(address,address,uint256,address)",
            address(USDC),
            address(WETH),
            BASE_USER_USDC_BALANCE,
            USER
        );

        uint256 initialNonce = GAS_TANK.nonces(USER);

        bytes memory sponsorSignature = _generateSignature(
            address(ROUTER),
            data,
            permitBatch,
            initialNonce,
            address(USDC),
            0,
            1900000000,
            USER_PK
        );

        vm.prank(USER);
        GAS_TANK.sponsorOrderedTransactions(
            address(ROUTER),
            data,
            permitBatch,
            permitSignature,
            USER,
            address(USDC),
            0,
            1900000000,
            sponsorSignature
        );

        assertEq(
            GAS_TANK.nonces(USER),
            initialNonce + 1,
            "Nonce not incremented"
        );
    }

    function testReplayAttack() public {
        IAllowanceTransfer.PermitDetails memory details = IAllowanceTransfer
            .PermitDetails({
                token: address(USDC),
                amount: uint160(BASE_USER_USDC_BALANCE),
                nonce: 0,
                expiration: 1900000000
            });

        IAllowanceTransfer.PermitDetails[]
            memory detailsArray = new IAllowanceTransfer.PermitDetails[](1);

        detailsArray[0] = details;

        (
            IAllowanceTransfer.PermitBatch memory permitBatch,
            bytes memory permitSignature
        ) = _generatePermitBatchSignature(detailsArray);

        bytes memory data = abi.encodeWithSignature(
            "swapTo(address,address,uint256,address)",
            address(USDC),
            address(WETH),
            BASE_USER_USDC_BALANCE,
            USER
        );

        bytes memory sponsorSignature = _generateSignature(
            address(ROUTER),
            data,
            permitBatch,
            GAS_TANK.nonces(USER),
            address(USDC),
            0,
            1900000000,
            USER_PK
        );

        vm.startPrank(SENDER);

        GAS_TANK.sponsorOrderedTransactions(
            address(ROUTER),
            data,
            permitBatch,
            permitSignature,
            USER,
            address(USDC),
            0,
            1900000000,
            sponsorSignature
        );

        assertEq(true, true);

        // Try to replay the same transaction
        vm.expectRevert(GeniusErrors.InvalidSignature.selector);
        GAS_TANK.sponsorOrderedTransactions(
            address(ROUTER),
            data,
            permitBatch,
            permitSignature,
            USER,
            address(USDC),
            0,
            1900000000,
            sponsorSignature
        );
        vm.stopPrank();
    }

    function _generatePermitBatchSignature(
        IAllowanceTransfer.PermitDetails[] memory details
    )
        internal
        view
        returns (IAllowanceTransfer.PermitBatch memory, bytes memory)
    {
        IAllowanceTransfer.PermitBatch memory permitBatch = IAllowanceTransfer
            .PermitBatch({
                details: details,
                spender: address(GAS_TANK),
                sigDeadline: 1900000000
            });

        bytes memory permitSignature = sigUtils.getPermitBatchSignature(
            permitBatch,
            USER_PK,
            DOMAIN_SEPERATOR
        );

        return (permitBatch, permitSignature);
    }

    function testAggregateWithPermit2() public {
        IAllowanceTransfer.PermitDetails memory details = IAllowanceTransfer
            .PermitDetails({
                token: address(DAI),
                amount: uint160(BASE_USER_DAI_BALANCE),
                nonce: 0,
                expiration: 1900000000
            });

        IAllowanceTransfer.PermitDetails[]
            memory detailsArray = new IAllowanceTransfer.PermitDetails[](1);

        detailsArray[0] = details;

        (
            IAllowanceTransfer.PermitBatch memory permitBatch,
            bytes memory permitSignature
        ) = _generatePermitBatchSignature(detailsArray);

        bytes memory data = abi.encodeWithSelector(
            ROUTER.swapTo.selector,
            address(DAI),
            address(WETH),
            BASE_USER_DAI_BALANCE - 1 ether,
            USER
        );

        vm.startPrank(USER);

        uint256 initialDAIBalance = DAI.balanceOf(USER);
        uint256 initialUSDCBalance = WETH.balanceOf(USER);

        GAS_TANK.aggregateWithPermit2(
            address(ROUTER),
            data,
            permitBatch,
            permitSignature,
            address(DAI),
            1 ether
        );

        assertEq(
            DAI.balanceOf(USER),
            initialDAIBalance - BASE_USER_DAI_BALANCE,
            "DAI balance should decrease"
        );
        assertEq(
            WETH.balanceOf(USER),
            initialUSDCBalance + BASE_ROUTER_WETH_BALANCE / 2,
            "WETH balance should increase"
        );
        assertEq(
            DAI.balanceOf(address(ROUTER)),
            BASE_USER_DAI_BALANCE - 1 ether,
            "Fee receiver should have received the fees"
        );
        assertEq(
            DAI.balanceOf(FEE_RECIPIENT),
            1 ether,
            "Fee receiver should have received the fees"
        );

        vm.stopPrank();
    }

    function testAggregateWithPermit2InvalidSignature() public {
        IAllowanceTransfer.PermitDetails memory details = IAllowanceTransfer
            .PermitDetails({
                token: address(DAI),
                amount: uint160(BASE_USER_DAI_BALANCE),
                nonce: 0,
                expiration: 1900000000
            });

        IAllowanceTransfer.PermitDetails[]
            memory detailsArray = new IAllowanceTransfer.PermitDetails[](1);

        detailsArray[0] = details;

        (
            IAllowanceTransfer.PermitBatch memory permitBatch,
            bytes memory permitSignature
        ) = _generatePermitBatchSignature(detailsArray);

        // Modify the signature to make it invalid
        permitSignature[0] = bytes1(uint8(permitSignature[0]) + 1);

        bytes memory data = abi.encodeWithSelector(
            ROUTER.swap.selector,
            address(DAI),
            address(USDC),
            BASE_USER_DAI_BALANCE
        );
        vm.startPrank(USER);

        vm.expectRevert(
            abi.encodeWithSelector(GeniusErrors.InvalidSignature.selector)
        );
        GAS_TANK.aggregateWithPermit2(
            address(ROUTER),
            data,
            permitBatch,
            permitSignature,
            address(DAI),
            1 ether
        );

        vm.stopPrank();
    }

    function testSponsorUnorderedTransactions() public {
        IAllowanceTransfer.PermitDetails memory details = IAllowanceTransfer
            .PermitDetails({
                token: address(USDC),
                amount: uint160(BASE_USER_USDC_BALANCE),
                nonce: 0,
                expiration: 1900000000
            });

        IAllowanceTransfer.PermitDetails[]
            memory detailsArray = new IAllowanceTransfer.PermitDetails[](1);
        detailsArray[0] = details;

        (
            IAllowanceTransfer.PermitBatch memory permitBatch,
            bytes memory permitSignature
        ) = _generatePermitBatchSignature(detailsArray);

        bytes memory data = abi.encodeWithSignature(
            "swapTo(address,address,uint256,address)",
            address(USDC),
            address(WETH),
            BASE_USER_USDC_BALANCE,
            USER
        );

        bytes32 seed = keccak256("test_seed");
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory sponsorSignature = _generateUnorderedSignature(
            address(ROUTER),
            data,
            permitBatch,
            seed,
            address(USDC),
            0,
            deadline,
            USER_PK
        );

        vm.startPrank(SENDER);

        GAS_TANK.sponsorUnorderedTransactions(
            address(ROUTER),
            data,
            permitBatch,
            permitSignature,
            USER,
            address(USDC),
            0,
            deadline,
            seed,
            sponsorSignature
        );

        assertEq(USDC.balanceOf(USER), 0, "USDC balance mismatch");
        assertEq(
            WETH.balanceOf(USER),
            BASE_ROUTER_WETH_BALANCE / 2,
            "WETH balance mismatch"
        );

        vm.stopPrank();
    }

    function testSponsorUnorderedTransactionsWithFee() public {
        IAllowanceTransfer.PermitDetails memory details = IAllowanceTransfer
            .PermitDetails({
                token: address(USDC),
                amount: uint160(BASE_USER_USDC_BALANCE),
                nonce: 0,
                expiration: 1900000000
            });

        IAllowanceTransfer.PermitDetails[]
            memory detailsArray = new IAllowanceTransfer.PermitDetails[](1);
        detailsArray[0] = details;

        (
            IAllowanceTransfer.PermitBatch memory permitBatch,
            bytes memory permitSignature
        ) = _generatePermitBatchSignature(detailsArray);

        bytes memory data = abi.encodeWithSignature(
            "swapTo(address,address,uint256,address)",
            address(USDC),
            address(WETH),
            BASE_USER_USDC_BALANCE - 1 ether,
            USER
        );

        bytes32 seed = keccak256("test_seed_with_fee");
        uint256 deadline = block.timestamp + 1 hours;
        uint256 feeAmount = 1 ether;

        bytes memory sponsorSignature = _generateUnorderedSignature(
            address(ROUTER),
            data,
            permitBatch,
            seed,
            address(USDC),
            feeAmount,
            deadline,
            USER_PK
        );

        vm.startPrank(SENDER);

        GAS_TANK.sponsorUnorderedTransactions(
            address(ROUTER),
            data,
            permitBatch,
            permitSignature,
            USER,
            address(USDC),
            feeAmount,
            deadline,
            seed,
            sponsorSignature
        );

        assertEq(
            USDC.balanceOf(FEE_RECIPIENT),
            feeAmount,
            "Fee not transferred correctly"
        );
        assertEq(
            USDC.balanceOf(address(ROUTER)),
            BASE_USER_USDC_BALANCE - feeAmount,
            "USDC balance mismatch"
        );
        assertEq(
            WETH.balanceOf(USER),
            BASE_ROUTER_WETH_BALANCE / 2,
            "WETH balance mismatch"
        );

        vm.stopPrank();
    }

    function testSponsorUnorderedTransactionsInvalidSignature() public {
        IAllowanceTransfer.PermitDetails memory details = IAllowanceTransfer
            .PermitDetails({
                token: address(USDC),
                amount: uint160(BASE_USER_USDC_BALANCE),
                nonce: 0,
                expiration: 1900000000
            });

        IAllowanceTransfer.PermitDetails[]
            memory detailsArray = new IAllowanceTransfer.PermitDetails[](1);
        detailsArray[0] = details;

        (
            IAllowanceTransfer.PermitBatch memory permitBatch,
            bytes memory permitSignature
        ) = _generatePermitBatchSignature(detailsArray);

        bytes memory data = abi.encodeWithSignature(
            "swapTo(address,address,uint256,address)",
            address(USDC),
            address(WETH),
            BASE_USER_USDC_BALANCE,
            USER
        );

        bytes32 seed = keccak256("test_seed_invalid_signature");
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory invalidSignature = abi.encodePacked(
            bytes32(0),
            bytes32(0),
            uint8(0)
        );

        vm.expectRevert(
            abi.encodeWithSelector(ECDSA.ECDSAInvalidSignature.selector)
        );
        GAS_TANK.sponsorUnorderedTransactions(
            address(ROUTER),
            data,
            permitBatch,
            permitSignature,
            USER,
            address(USDC),
            0,
            deadline,
            seed,
            invalidSignature
        );
    }

    function testSponsorUnorderedTransactionsExpiredDeadline() public {
        IAllowanceTransfer.PermitDetails memory details = IAllowanceTransfer
            .PermitDetails({
                token: address(USDC),
                amount: uint160(BASE_USER_USDC_BALANCE),
                nonce: 0,
                expiration: 1900000000
            });

        IAllowanceTransfer.PermitDetails[]
            memory detailsArray = new IAllowanceTransfer.PermitDetails[](1);
        detailsArray[0] = details;

        (
            IAllowanceTransfer.PermitBatch memory permitBatch,
            bytes memory permitSignature
        ) = _generatePermitBatchSignature(detailsArray);

        bytes memory data = abi.encodeWithSignature(
            "swapTo(address,address,uint256,address)",
            address(USDC),
            address(WETH),
            BASE_USER_USDC_BALANCE,
            USER
        );

        bytes32 seed = keccak256("test_seed_expired_deadline");
        uint256 expiredDeadline = block.timestamp - 1;

        bytes memory sponsorSignature = _generateUnorderedSignature(
            address(ROUTER),
            data,
            permitBatch,
            seed,
            address(USDC),
            0,
            expiredDeadline,
            USER_PK
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                GeniusErrors.DeadlinePassed.selector,
                expiredDeadline
            )
        );
        GAS_TANK.sponsorUnorderedTransactions(
            address(ROUTER),
            data,
            permitBatch,
            permitSignature,
            USER,
            address(USDC),
            0,
            expiredDeadline,
            seed,
            sponsorSignature
        );
    }

    function testSponsorUnorderedTransactionsInvalidSeed() public {
        IAllowanceTransfer.PermitDetails memory details = IAllowanceTransfer
            .PermitDetails({
                token: address(USDC),
                amount: uint160(BASE_USER_USDC_BALANCE),
                nonce: 0,
                expiration: 1900000000
            });

        IAllowanceTransfer.PermitDetails[]
            memory detailsArray = new IAllowanceTransfer.PermitDetails[](1);
        detailsArray[0] = details;

        (
            IAllowanceTransfer.PermitBatch memory permitBatch,
            bytes memory permitSignature
        ) = _generatePermitBatchSignature(detailsArray);

        bytes memory data = abi.encodeWithSignature(
            "swapTo(address,address,uint256,address)",
            address(USDC),
            address(WETH),
            BASE_USER_USDC_BALANCE,
            USER
        );

        bytes32 seed = keccak256("test_seed_invalid");
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory sponsorSignature = _generateUnorderedSignature(
            address(ROUTER),
            data,
            permitBatch,
            seed,
            address(USDC),
            0,
            deadline,
            USER_PK
        );

        // First transaction should succeed
        GAS_TANK.sponsorUnorderedTransactions(
            address(ROUTER),
            data,
            permitBatch,
            permitSignature,
            USER,
            address(USDC),
            0,
            deadline,
            seed,
            sponsorSignature
        );

        // Second transaction with the same seed should fail
        vm.expectRevert(GeniusErrors.InvalidSeed.selector);
        GAS_TANK.sponsorUnorderedTransactions(
            address(ROUTER),
            data,
            permitBatch,
            permitSignature,
            USER,
            address(USDC),
            0,
            deadline,
            seed,
            sponsorSignature
        );
    }

    function _generateSignature(
        address target,
        bytes memory data,
        IAllowanceTransfer.PermitBatch memory permitBatch,
        uint256 nonce,
        address feeToken,
        uint256 feeAmount,
        uint256 deadline,
        uint256 privateKey
    ) internal view returns (bytes memory) {
        bytes32 messageHash = keccak256(
            abi.encode(
                target,
                data,
                permitBatch,
                nonce,
                feeToken,
                feeAmount,
                deadline,
                address(GAS_TANK)
            )
        );

        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            ethSignedMessageHash
        );
        return abi.encodePacked(r, s, v);
    }

    function _generateUnorderedSignature(
        address target,
        bytes memory data,
        IAllowanceTransfer.PermitBatch memory permitBatch,
        bytes32 seed,
        address feeToken,
        uint256 feeAmount,
        uint256 deadline,
        uint256 privateKey
    ) internal view returns (bytes memory) {
        bytes32 messageHash = keccak256(
            abi.encode(
                target,
                data,
                permitBatch,
                seed,
                feeToken,
                feeAmount,
                deadline,
                address(GAS_TANK)
            )
        );

        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            ethSignedMessageHash
        );
        return abi.encodePacked(r, s, v);
    }

    function _encodeTransactions(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory dataArray
    ) internal pure returns (bytes memory) {
        require(
            targets.length == values.length &&
                values.length == dataArray.length,
            "Array lengths must match"
        );

        bytes memory encoded = new bytes(0);

        for (uint i = 0; i < targets.length; i++) {
            encoded = abi.encodePacked(
                encoded,
                uint8(0), // operation (0 for call)
                targets[i],
                values[i],
                uint256(dataArray[i].length),
                dataArray[i]
            );
        }

        bytes memory data = abi.encodeWithSelector(
            GeniusProxyCall.multiSend.selector,
            encoded
        );

        return data;
    }
}
