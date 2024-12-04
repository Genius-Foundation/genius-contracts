// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import {Test} from "forge-std/Test.sol";
import {GeniusMulticall} from "../src/GeniusMulticall.sol";
import {MockDEXRouter} from "./mocks/MockDEXRouter.sol";
import {IAllowanceTransfer} from "permit2/interfaces/IAllowanceTransfer.sol";
import {PermitSignature} from "./utils/SigUtils.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IEIP712} from "permit2/interfaces/IEIP712.sol";
import {GeniusErrors} from "../src/libs/GeniusErrors.sol";

contract GeniusMulticallTest is Test {
    uint256 constant BASE_USER_USDC_BALANCE = 100 ether;
    uint256 constant BASE_USER_DAI_BALANCE = 100 ether;
    uint256 constant BASE_ROUTER_WETH_BALANCE = 100 ether;

    bytes32 public DOMAIN_SEPERATOR;

    uint256 avalanche;
    string private rpc = vm.envString("AVALANCHE_RPC_URL");

    IEIP712 public PERMIT2;
    PermitSignature public sigUtils;

    GeniusMulticall public MULTICALL;
    ERC20 public USDC;
    ERC20 public WETH;
    ERC20 public DAI;

    MockDEXRouter ROUTER;
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

        MULTICALL = new GeniusMulticall(address(PERMIT2));
        USDC = ERC20(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E);
        WETH = ERC20(0x49D5c2BdFfac6CE2BFdB6640F4F80f226bc10bAB);
        DAI = ERC20(0xd586E7F844cEa2F87f50152665BCbc2C279D8d70);
        sigUtils = new PermitSignature();

        deal(address(USDC), USER, BASE_USER_USDC_BALANCE);
        deal(address(DAI), USER, BASE_USER_DAI_BALANCE);
        deal(address(WETH), address(ROUTER), BASE_ROUTER_WETH_BALANCE);

        vm.startPrank(USER);
        USDC.approve(address(PERMIT2), type(uint256).max);
        DAI.approve(address(PERMIT2), type(uint256).max);
        vm.stopPrank();
    }

    function testExecuteWithPermit2SingleToken() public {
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

        bytes[] memory dataArray = new bytes[](2);
        dataArray[0] = abi.encodeWithSignature(
            "approve(address,uint256)",
            address(ROUTER),
            BASE_USER_USDC_BALANCE
        );
        dataArray[1] = abi.encodeWithSignature(
            "swapTo(address,address,uint256,address)",
            address(USDC),
            address(WETH),
            BASE_USER_USDC_BALANCE,
            USER
        );

        address[] memory targets = new address[](2);
        targets[0] = address(USDC);
        targets[1] = address(ROUTER);

        vm.prank(USER);
        MULTICALL.executeWithPermit2(
            address(MULTICALL),
            _encodeTransactions(targets, new uint256[](2), dataArray),
            permitBatch,
            permitSignature
        );

        assertEq(USDC.balanceOf(USER), 0, "USDC balance mismatch");
        assertEq(
            WETH.balanceOf(USER),
            BASE_ROUTER_WETH_BALANCE / 2,
            "WETH balance mismatch"
        );
    }

    function testExecuteWithPermit2MultipleTokensMulticall() public {
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

        // Create multicall transaction data
        address[] memory targets = new address[](4);
        bytes[] memory dataArray = new bytes[](4);

        targets[0] = address(USDC);
        targets[1] = address(DAI);
        dataArray[0] = abi.encodeWithSignature(
            "approve(address,uint256)",
            address(ROUTER),
            BASE_USER_USDC_BALANCE
        );
        dataArray[1] = abi.encodeWithSignature(
            "approve(address,uint256)",
            address(ROUTER),
            BASE_USER_DAI_BALANCE
        );

        // First swap: USDC to WETH
        targets[2] = address(ROUTER);
        dataArray[2] = abi.encodeWithSignature(
            "swapTo(address,address,uint256,address)",
            address(USDC),
            address(WETH),
            BASE_USER_USDC_BALANCE,
            USER
        );

        // Second swap: DAI to WETH
        targets[3] = address(ROUTER);
        dataArray[3] = abi.encodeWithSignature(
            "swapTo(address,address,uint256,address)",
            address(DAI),
            address(WETH),
            BASE_USER_DAI_BALANCE,
            USER
        );

        bytes memory multicallData = _encodeTransactions(
            targets,
            new uint256[](4),
            dataArray
        );

        vm.prank(USER);
        MULTICALL.executeWithPermit2(
            address(MULTICALL),
            multicallData,
            permitBatch,
            permitSignature
        );

        assertEq(USDC.balanceOf(USER), 0, "USDC balance mismatch");
        assertEq(DAI.balanceOf(USER), 0, "DAI balance mismatch");
        assertEq(
            WETH.balanceOf(USER),
            (BASE_ROUTER_WETH_BALANCE * 75) / 100,
            "WETH balance mismatch"
        );
    }

    function testExecuteWithPermit2AddressZeroTarget() public {
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
            USER,
            BASE_USER_USDC_BALANCE
        );

        vm.expectRevert(GeniusErrors.NonAddress0.selector);
        MULTICALL.executeWithPermit2(
            address(0),
            data,
            permitBatch,
            permitSignature
        );
    }

    function testMultiSendDirectCallRevert() public {
        address[] memory targets = new address[](1);
        bytes[] memory dataArray = new bytes[](1);
        uint256[] memory values = new uint256[](1);

        targets[0] = address(ROUTER);
        dataArray[0] = abi.encodeWithSignature(
            "swapTo(address,address,uint256,address)",
            address(USDC),
            address(WETH),
            BASE_USER_USDC_BALANCE,
            USER
        );
        values[0] = 0;

        bytes memory multicallData = _encodeTransactions(
            targets,
            values,
            dataArray
        );

        // Try to call multiSend directly
        vm.prank(USER);
        vm.expectRevert(GeniusErrors.InvalidCallerMulticall.selector);
        MULTICALL.multiSend(multicallData);
    }

    function testExecuteWithPermit2InvalidSpender() public {
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

        IAllowanceTransfer.PermitBatch memory permitBatch = IAllowanceTransfer
            .PermitBatch({
                details: detailsArray,
                spender: USER, // Invalid spender
                sigDeadline: 1900000000
            });

        bytes memory permitSignature = sigUtils.getPermitBatchSignature(
            permitBatch,
            USER_PK,
            DOMAIN_SEPERATOR
        );

        bytes memory data = abi.encodeWithSignature(
            "transfer(address,uint256)",
            USER,
            BASE_USER_USDC_BALANCE
        );

        vm.expectRevert(GeniusErrors.InvalidSpender.selector);
        MULTICALL.executeWithPermit2(
            address(ROUTER),
            data,
            permitBatch,
            permitSignature
        );
    }

    function testExecuteWithPermit2RemainingFunds() public {
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

        // Create multicall that only uses part of the permitted tokens
        bytes[] memory dataArray = new bytes[](2);
        dataArray[0] = abi.encodeWithSignature(
            "approve(address,uint256)",
            address(ROUTER),
            BASE_USER_USDC_BALANCE / 2 // Only approve half
        );
        dataArray[1] = abi.encodeWithSignature(
            "swapTo(address,address,uint256,address)",
            address(USDC),
            address(WETH),
            BASE_USER_USDC_BALANCE / 2, // Only swap half
            USER
        );

        address[] memory targets = new address[](2);
        targets[0] = address(USDC);
        targets[1] = address(ROUTER);

        vm.prank(USER);
        MULTICALL.executeWithPermit2(
            address(MULTICALL),
            _encodeTransactions(targets, new uint256[](2), dataArray),
            permitBatch,
            permitSignature
        );

        // Verify remaining USDC was returned to user
        assertEq(
            USDC.balanceOf(USER),
            BASE_USER_USDC_BALANCE / 2,
            "Remaining USDC not returned to user"
        );
        // Verify WETH from swap was received
        assertEq(
            WETH.balanceOf(USER),
            BASE_ROUTER_WETH_BALANCE / 2,
            "WETH balance mismatch"
        );
        // Verify no tokens left in multicall contract
        assertEq(
            USDC.balanceOf(address(MULTICALL)),
            0,
            "Tokens left in multicall contract"
        );
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
                spender: address(MULTICALL),
                sigDeadline: 1900000000
            });

        bytes memory permitSignature = sigUtils.getPermitBatchSignature(
            permitBatch,
            USER_PK,
            DOMAIN_SEPERATOR
        );

        return (permitBatch, permitSignature);
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
            GeniusMulticall.multiSend.selector,
            encoded
        );

        return data;
    }

    receive() external payable {}
}
