// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import {Test, console} from "forge-std/Test.sol";
import {GeniusMulticall} from "../src/GeniusMulticall.sol";
import {GeniusGasTank} from "../src/GeniusGasTank.sol";
import {MockDEXRouter} from "./mocks/MockDEXRouter.sol";
import {IAllowanceTransfer} from "permit2/interfaces/IAllowanceTransfer.sol";
import {PermitSignature} from "./utils/SigUtils.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IEIP712} from "permit2/interfaces/IEIP712.sol";

contract GeniusGasTankTest is Test {
    uint256 BASE_USER_USDC_BALANCE = 100 ether;
    uint256 BASE_ROUTER_WETH_BALANCE = 100 ether;

    bytes32 public DOMAIN_SEPERATOR;

    uint256 avalanche;
    string private rpc = vm.envString("AVALANCHE_RPC_URL");

    IEIP712 public PERMIT2;
    PermitSignature public sigUtils;

    GeniusMulticall public MULTICALL;
    GeniusGasTank public GAS_TANK;
    ERC20 public USDC;
    ERC20 public WETH;

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
        deal(address(WETH), address(ROUTER), BASE_ROUTER_WETH_BALANCE);

        vm.startPrank(USER);
        USDC.approve(address(PERMIT2), type(uint256).max);
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

        // Build swap transaction

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

        // Build signature

        bytes memory sponsorSignature = _generateSignature(
            targets,
            data,
            values,
            permitBatch,
            GAS_TANK.nonces(USER),
            1900000000,
            USER_PK
        );

        vm.startPrank(USER);

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
}
