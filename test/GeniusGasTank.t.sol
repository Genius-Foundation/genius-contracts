// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import {Test} from "forge-std/Test.sol";
import {GeniusMulticall} from "../src/GeniusMulticall.sol";
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

    GeniusMulticall public MULTICALL;
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

        MULTICALL = new GeniusMulticall();
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
            address(MULTICALL),
            allowedTargets
        );

        deal(address(USDC), USER, BASE_USER_USDC_BALANCE);
        deal(address(DAI), USER, BASE_USER_DAI_BALANCE);
        deal(address(WETH), address(ROUTER), BASE_ROUTER_WETH_BALANCE);

        vm.startPrank(USER);
        USDC.approve(address(PERMIT2), type(uint256).max);
        DAI.approve(address(PERMIT2), type(uint256).max);
        vm.stopPrank();
    }

    function testCalldataFromTheOutside() public {
        bytes
            memory data = hex"b0e0f98600000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000180000000000000000000000000000000000000000000000000000000000000024000000000000000000000000000000000000000000000000000000000000002800000000000000000000000000000000000000000000000000000000000000380000000000000000000000000b0e62f5c874b7edea2e977567c283aae140bba7e000000000000000000000000b97ef9ef8734c71904d8002f8b6bc66dd9c48a6e000000000000000000000000000000000000000000000000000000000000a713000000000000000000000000000000000000000000000000000000006712d67300000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000b97ef9ef8734c71904d8002f8b6bc66dd9c48a6e000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000044a9059cbb0000000000000000000000005cc11ef1de86c5e00259a463ac3f3ae1a0fa290900000000000000000000000000000000000000000000000000000000000000640000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006000000000000000000000000040ac0641cf13b47522a7da57b2ff392bc6e4dd8f000000000000000000000000000000000000000000000000000000006712d6730000000000000000000000000000000000000000000000000000000000000001000000000000000000000000b97ef9ef8734c71904d8002f8b6bc66dd9c48a6e0000000000000000000000000000000000000000000000000000000000022db3000000000000000000000000000000000000000000000000000000006712d6730000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004172fb24a085a1a78ec680dc55c46894d0d41f4866b3c94e4fe827b95d078f55cf1619b040b65a9b7f516bedd1e5dc9f684d3f09021191cbacd5da01d8b945092e1b000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000041930f69cd99d08fafa40458d4b67e3cb460ea1edd0aa038f0c8c7e215c8a9771d1138ff059e1f50c5bc4081442f2c67e5f8f92d8fc94722f679d5a8527325ee101b00000000000000000000000000000000000000000000000000000000000000";

        (bool success, bytes memory result) = address(GAS_TANK).call(data);
        assertEq(success, true, "Please work");
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

        address[] memory targets = new address[](1);
        bytes[] memory data = new bytes[](1);
        uint256[] memory values = new uint256[](1);

        targets[0] = address(USDC);
        data[0] = abi.encodeWithSignature(
            "transfer(address,uint256)",
            address(ROUTER),
            BASE_USER_USDC_BALANCE
        );
        values[0] = 0;

        bytes memory sponsorSignature = _generateSignature(
            targets,
            data,
            values,
            permitBatch,
            GAS_TANK.nonces(USER),
            address(USDC),
            0,
            1900000000,
            USER_PK
        );

        vm.startPrank(SENDER);

        GAS_TANK.sponsorTransactions(
            targets,
            data,
            values,
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

        address[] memory targets = new address[](2);
        bytes[] memory data = new bytes[](2);
        uint256[] memory values = new uint256[](2);

        targets[0] = address(USDC);
        data[0] = abi.encodeWithSignature(
            "approve(address,uint256)",
            address(ROUTER),
            BASE_USER_USDC_BALANCE
        );
        targets[1] = address(ROUTER);
        data[1] = abi.encodeWithSignature(
            "swapTo(address,address,uint256,address)",
            address(USDC),
            address(WETH),
            BASE_USER_USDC_BALANCE,
            USER
        );
        values[0] = 0;
        values[1] = 0;

        bytes memory sponsorSignature = _generateSignature(
            targets,
            data,
            values,
            permitBatch,
            GAS_TANK.nonces(USER),
            address(USDC),
            0,
            1900000000,
            USER_PK
        );

        vm.startPrank(SENDER);

        GAS_TANK.sponsorTransactions(
            targets,
            data,
            values,
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

        address[] memory targets = new address[](2);
        bytes[] memory data = new bytes[](2);
        uint256[] memory values = new uint256[](2);

        targets[0] = address(USDC);
        data[0] = abi.encodeWithSignature(
            "approve(address,uint256)",
            address(ROUTER),
            BASE_USER_USDC_BALANCE - 1 ether
        );
        targets[1] = address(ROUTER);
        data[1] = abi.encodeWithSignature(
            "swapTo(address,address,uint256,address)",
            address(USDC),
            address(WETH),
            BASE_USER_USDC_BALANCE - 1 ether,
            USER
        );
        values[0] = 0;
        values[1] = 0;

        bytes memory sponsorSignature = _generateSignature(
            targets,
            data,
            values,
            permitBatch,
            GAS_TANK.nonces(USER),
            address(USDC),
            1 ether,
            1900000000,
            USER_PK
        );

        vm.startPrank(SENDER);

        GAS_TANK.sponsorTransactions(
            targets,
            data,
            values,
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

    function testSponsorFailsIfNoMulticallApproval() public {
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

        // Build swap transaction

        address[] memory targets = new address[](1);
        bytes[] memory data = new bytes[](1);
        uint256[] memory values = new uint256[](1);

        targets[0] = address(ROUTER);
        data[0] = abi.encodeWithSignature(
            "swapTo(address,address,uint256,address)",
            address(USDC),
            address(WETH),
            BASE_USER_USDC_BALANCE,
            USER
        );
        values[0] = 0;

        // Build signature

        bytes memory sponsorSignature = _generateSignature(
            targets,
            data,
            values,
            permitBatch,
            GAS_TANK.nonces(USER),
            address(USDC),
            0,
            1900000000,
            USER_PK
        );

        vm.startPrank(SENDER);

        vm.expectRevert(
            abi.encodeWithSelector(
                GeniusErrors.ExternalCallFailed.selector,
                address(ROUTER),
                0
            )
        );
        // Call sponsorSwap
        GAS_TANK.sponsorTransactions(
            targets,
            data,
            values,
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

        address[] memory targets = new address[](2);
        bytes[] memory data = new bytes[](2);
        uint256[] memory values = new uint256[](2);

        targets[0] = address(USDC);
        data[0] = abi.encodeWithSignature(
            "approve(address,uint256)",
            address(ROUTER),
            BASE_USER_USDC_BALANCE
        );
        targets[1] = address(ROUTER);
        data[1] = abi.encodeWithSignature(
            "swapTo(address,address,uint256,address)",
            address(USDC),
            address(WETH),
            BASE_USER_USDC_BALANCE - 1 ether,
            USER
        );
        values[0] = 0;
        values[1] = 0;

        uint256 feeAmount = 1 ether;

        bytes memory sponsorSignature = _generateSignature(
            targets,
            data,
            values,
            permitBatch,
            GAS_TANK.nonces(USER),
            address(USDC),
            feeAmount,
            1900000000,
            USER_PK
        );

        vm.startPrank(SENDER);

        GAS_TANK.sponsorTransactions(
            targets,
            data,
            values,
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

        address[] memory targets = new address[](2);
        bytes[] memory data = new bytes[](2);
        uint256[] memory values = new uint256[](2);

        targets[0] = address(USDC);
        data[0] = abi.encodeWithSignature(
            "approve(address,uint256)",
            address(ROUTER),
            BASE_USER_USDC_BALANCE
        );
        targets[1] = address(ROUTER);
        data[1] = abi.encodeWithSignature(
            "swapTo(address,address,uint256,address)",
            address(USDC),
            address(WETH),
            BASE_USER_USDC_BALANCE,
            USER
        );
        values[0] = 0;
        values[1] = 0;

        bytes memory invalidSignature = abi.encodePacked(
            bytes32(0),
            bytes32(0),
            uint8(0)
        );

        //revert with ECDSAInvalidSignature()
        vm.expectRevert(
            abi.encodeWithSelector(ECDSA.ECDSAInvalidSignature.selector)
        );
        GAS_TANK.sponsorTransactions(
            targets,
            data,
            values,
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

        address[] memory targets = new address[](2);
        bytes[] memory data = new bytes[](2);
        uint256[] memory values = new uint256[](2);

        targets[0] = address(USDC);
        data[0] = abi.encodeWithSignature(
            "approve(address,uint256)",
            address(ROUTER),
            BASE_USER_USDC_BALANCE
        );
        targets[1] = address(ROUTER);
        data[1] = abi.encodeWithSignature(
            "swapTo(address,address,uint256,address)",
            address(USDC),
            address(WETH),
            BASE_USER_USDC_BALANCE,
            USER
        );
        values[0] = 0;
        values[1] = 0;

        uint256 expiredDeadline = block.timestamp - 1;

        bytes memory sponsorSignature = _generateSignature(
            targets,
            data,
            values,
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
        GAS_TANK.sponsorTransactions(
            targets,
            data,
            values,
            permitBatch,
            permitSignature,
            USER,
            address(USDC),
            0,
            expiredDeadline,
            sponsorSignature
        );
    }

    function testSponsorSwapUnauthorizedTarget() public {
        address unauthorizedTarget = makeAddr("UNAUTHORIZED");

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

        address[] memory targets = new address[](1);
        bytes[] memory data = new bytes[](1);
        uint256[] memory values = new uint256[](1);

        targets[0] = unauthorizedTarget;
        data[0] = abi.encodeWithSignature("someFunction()");
        values[0] = 0;

        bytes memory sponsorSignature = _generateSignature(
            targets,
            data,
            values,
            permitBatch,
            GAS_TANK.nonces(USER),
            address(USDC),
            0,
            1900000000,
            USER_PK
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                GeniusErrors.InvalidTarget.selector,
                unauthorizedTarget
            )
        );
        GAS_TANK.sponsorTransactions(
            targets,
            data,
            values,
            permitBatch,
            permitSignature,
            USER,
            address(USDC),
            0,
            1900000000,
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

        bytes memory sponsorSignature = _generateSignature(
            targets,
            data,
            values,
            permitBatch,
            GAS_TANK.nonces(USER),
            address(USDC),
            0,
            1900000000,
            USER_PK
        );

        vm.startPrank(USER);

        GAS_TANK.sponsorTransactions(
            targets,
            data,
            values,
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

        address[] memory targets = new address[](2);
        bytes[] memory data = new bytes[](2);
        uint256[] memory values = new uint256[](2);

        targets[0] = address(USDC);
        data[0] = abi.encodeWithSignature(
            "approve(address,uint256)",
            address(ROUTER),
            BASE_USER_USDC_BALANCE
        );
        targets[1] = address(ROUTER);
        data[1] = abi.encodeWithSignature(
            "swapTo(address,address,uint256,address)",
            address(USDC),
            address(WETH),
            BASE_USER_USDC_BALANCE,
            USER
        );
        values[0] = 0;
        values[1] = 0;

        bytes memory sponsorSignature = _generateSignature(
            targets,
            data,
            values,
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
        GAS_TANK.sponsorTransactions(
            targets,
            data,
            values,
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
        GAS_TANK.sponsorTransactions(
            targets,
            data,
            values,
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

        address[] memory targets = new address[](2);
        bytes[] memory data = new bytes[](2);
        uint256[] memory values = new uint256[](2);

        targets[0] = address(USDC);
        data[0] = abi.encodeWithSignature(
            "approve(address,uint256)",
            address(ROUTER),
            BASE_USER_USDC_BALANCE - 1 ether
        );
        targets[1] = address(ROUTER);
        data[1] = abi.encodeWithSignature(
            "swapTo(address,address,uint256,address)",
            address(USDC),
            address(WETH),
            BASE_USER_USDC_BALANCE - 1 ether,
            USER
        );
        values[0] = 0;
        values[1] = 0;

        uint256 feeAmount = 1 ether;

        bytes memory sponsorSignature = _generateSignature(
            targets,
            data,
            values,
            permitBatch,
            GAS_TANK.nonces(USER),
            address(USDC),
            feeAmount,
            1900000000,
            USER_PK
        );

        vm.prank(USER);
        GAS_TANK.sponsorTransactions(
            targets,
            data,
            values,
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

    function testSetAllowedTarget() public {
        address newTarget = makeAddr("NEW_TARGET");

        vm.prank(ADMIN);
        GAS_TANK.setAllowedTarget(newTarget, true);

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

        address[] memory targets = new address[](1);
        bytes[] memory data = new bytes[](1);
        uint256[] memory values = new uint256[](1);

        targets[0] = newTarget;
        data[0] = abi.encodeWithSignature("dummyFunction()");
        values[0] = 0;

        bytes memory sponsorSignature = _generateSignature(
            targets,
            data,
            values,
            permitBatch,
            GAS_TANK.nonces(USER),
            address(USDC),
            0,
            1900000000,
            USER_PK
        );

        vm.mockCall(
            newTarget,
            abi.encodeWithSignature("dummyFunction()"),
            abi.encode()
        );

        vm.prank(USER);
        GAS_TANK.sponsorTransactions(
            targets,
            data,
            values,
            permitBatch,
            permitSignature,
            USER,
            address(USDC),
            0,
            1900000000,
            sponsorSignature
        );
    }

    function testSetAllowedTargetUnauthorized() public {
        address newTarget = makeAddr("NEW_TARGET");

        vm.prank(USER);
        vm.expectRevert(GeniusErrors.IsNotAdmin.selector);
        GAS_TANK.setAllowedTarget(newTarget, true);
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

        address[] memory targets = new address[](2);
        bytes[] memory data = new bytes[](2);
        uint256[] memory values = new uint256[](2);

        targets[0] = address(USDC);
        data[0] = abi.encodeWithSignature(
            "approve(address,uint256)",
            address(ROUTER),
            BASE_USER_USDC_BALANCE
        );
        targets[1] = address(ROUTER);
        data[1] = abi.encodeWithSignature(
            "swapTo(address,address,uint256,address)",
            address(USDC),
            address(WETH),
            BASE_USER_USDC_BALANCE,
            USER
        );
        values[0] = 0;
        values[1] = 0;

        uint256 initialNonce = GAS_TANK.nonces(USER);

        bytes memory sponsorSignature = _generateSignature(
            targets,
            data,
            values,
            permitBatch,
            initialNonce,
            address(USDC),
            0,
            1900000000,
            USER_PK
        );

        vm.prank(USER);
        GAS_TANK.sponsorTransactions(
            targets,
            data,
            values,
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

        address[] memory targets = new address[](2);
        bytes[] memory data = new bytes[](2);
        uint256[] memory values = new uint256[](2);

        targets[0] = address(USDC);
        data[0] = abi.encodeWithSignature(
            "approve(address,uint256)",
            address(ROUTER),
            BASE_USER_USDC_BALANCE
        );
        targets[1] = address(ROUTER);
        data[1] = abi.encodeWithSignature(
            "swapTo(address,address,uint256,address)",
            address(USDC),
            address(WETH),
            BASE_USER_USDC_BALANCE,
            USER
        );
        values[0] = 0;
        values[1] = 0;

        bytes memory sponsorSignature = _generateSignature(
            targets,
            data,
            values,
            permitBatch,
            GAS_TANK.nonces(USER),
            address(USDC),
            0,
            1900000000,
            USER_PK
        );

        vm.startPrank(SENDER);

        GAS_TANK.sponsorTransactions(
            targets,
            data,
            values,
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
        GAS_TANK.sponsorTransactions(
            targets,
            data,
            values,
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

    function _generateSignature(
        address[] memory targets,
        bytes[] memory data,
        uint256[] memory values,
        IAllowanceTransfer.PermitBatch memory permitBatch,
        uint256 nonce,
        address feeToken,
        uint256 feeAmount,
        uint256 deadline,
        uint256 privateKey
    ) internal view returns (bytes memory) {
        bytes32 messageHash = keccak256(
            abi.encode(
                targets,
                data,
                values,
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

        address[] memory targets = new address[](2);
        bytes[] memory data = new bytes[](2);
        uint256[] memory values = new uint256[](2);

        targets[0] = address(DAI);
        data[0] = abi.encodeWithSelector(
            DAI.approve.selector,
            address(ROUTER),
            BASE_USER_DAI_BALANCE
        );
        targets[1] = address(ROUTER);
        data[1] = abi.encodeWithSelector(
            ROUTER.swapTo.selector,
            address(DAI),
            address(WETH),
            BASE_USER_DAI_BALANCE - 1 ether,
            USER
        );
        values[0] = 0;
        values[1] = 0;

        vm.startPrank(USER);

        uint256 initialDAIBalance = DAI.balanceOf(USER);
        uint256 initialUSDCBalance = WETH.balanceOf(USER);

        GAS_TANK.aggregateWithPermit2(
            targets,
            data,
            values,
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

        address[] memory targets = new address[](2);
        bytes[] memory data = new bytes[](2);
        uint256[] memory values = new uint256[](2);

        targets[0] = address(DAI);
        data[0] = abi.encodeWithSelector(
            DAI.approve.selector,
            address(ROUTER),
            BASE_USER_DAI_BALANCE
        );
        targets[1] = address(ROUTER);
        data[1] = abi.encodeWithSelector(
            ROUTER.swap.selector,
            address(DAI),
            address(USDC),
            BASE_USER_DAI_BALANCE
        );
        values[0] = 0;
        values[1] = 0;

        vm.startPrank(USER);

        vm.expectRevert(
            abi.encodeWithSelector(GeniusErrors.InvalidSignature.selector)
        );
        GAS_TANK.aggregateWithPermit2(
            targets,
            data,
            values,
            permitBatch,
            permitSignature,
            address(DAI),
            1 ether
        );

        vm.stopPrank();
    }
}
