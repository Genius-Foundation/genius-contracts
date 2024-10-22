// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import {Test, console} from "forge-std/Test.sol";
import {GeniusProxyCall} from "../src/GeniusProxyCall.sol";
import {MockDEXRouter} from "./mocks/MockDEXRouter.sol";
import {IAllowanceTransfer} from "permit2/interfaces/IAllowanceTransfer.sol";
import {PermitSignature} from "./utils/SigUtils.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IEIP712} from "permit2/interfaces/IEIP712.sol";
import {GeniusErrors} from "../src/libs/GeniusErrors.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {GeniusRouter} from "../src/GeniusRouter.sol";
import {GeniusVault} from "../src/GeniusVault.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IGeniusVault} from "../src/interfaces/IGeniusVault.sol";

contract GeniusRouterTest is Test {
    uint256 constant BASE_USER_WETH_BALANCE = 100 ether;
    uint256 constant BASE_USER_DAI_BALANCE = 100 ether;
    uint256 constant BASE_ROUTER_USDC_BALANCE = 100 ether;
    uint256 constant destChainId = 1;

    bytes32 public DOMAIN_SEPERATOR;

    uint256 avalanche;
    string private rpc = vm.envString("AVALANCHE_RPC_URL");

    IEIP712 public PERMIT2;
    PermitSignature public sigUtils;

    GeniusProxyCall public PROXYCALL;
    GeniusRouter public GENIUS_ROUTER;
    GeniusVault public GENIUS_VAULT;

    ERC20 public USDC;
    ERC20 public WETH;
    ERC20 public DAI;

    MockDEXRouter DEX_ROUTER;
    address ADMIN = makeAddr("ADMIN");
    address SENDER = makeAddr("SENDER");
    address FEE_RECIPIENT = makeAddr("FEE_RECIPIENT");

    address USER;
    uint256 USER_PK;

    bytes32 RECEIVER;
    bytes32 TOKEN_OUT;
    bytes32 TOKEN_IN;

    function setUp() public {
        avalanche = vm.createFork(rpc);

        vm.selectFork(avalanche);
        assertEq(vm.activeFork(), avalanche);

        (USER, USER_PK) = makeAddrAndKey("user");

        DEX_ROUTER = new MockDEXRouter();
        PERMIT2 = IEIP712(0x000000000022D473030F116dDEE9F6B43aC78BA3);
        DOMAIN_SEPERATOR = PERMIT2.DOMAIN_SEPARATOR();

        PROXYCALL = new GeniusProxyCall();
        USDC = ERC20(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E);
        WETH = ERC20(0x49D5c2BdFfac6CE2BFdB6640F4F80f226bc10bAB);
        DAI = ERC20(0xd586E7F844cEa2F87f50152665BCbc2C279D8d70);
        sigUtils = new PermitSignature();

        vm.startPrank(ADMIN, ADMIN);

        GeniusVault implementation = new GeniusVault();

        bytes memory data = abi.encodeWithSelector(
            GeniusVault.initialize.selector,
            address(USDC),
            ADMIN,
            address(PROXYCALL),
            7_500,
            30,
            300
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);

        GENIUS_VAULT = GeniusVault(address(proxy));
        GENIUS_ROUTER = new GeniusRouter(
            address(PERMIT2),
            address(GENIUS_VAULT),
            address(PROXYCALL)
        );

        RECEIVER = GENIUS_VAULT.addressToBytes32(USER);
        TOKEN_OUT = GENIUS_VAULT.addressToBytes32(address(USDC));
        TOKEN_IN = TOKEN_OUT;

        deal(address(USDC), address(DEX_ROUTER), BASE_ROUTER_USDC_BALANCE);
        deal(address(DAI), USER, BASE_USER_DAI_BALANCE);
        deal(address(WETH), USER, BASE_USER_WETH_BALANCE);

        vm.startPrank(USER);
        USDC.approve(address(PERMIT2), type(uint256).max);
        DAI.approve(address(PERMIT2), type(uint256).max);
        vm.stopPrank();
    }

    function testSwapAndCreateOrder() public {
        address[] memory tokensIn = new address[](1);
        uint256[] memory amountsIn = new uint256[](1);

        tokensIn[0] = address(DAI);
        amountsIn[0] = BASE_USER_DAI_BALANCE;

        bytes memory data = abi.encodeWithSelector(
            DEX_ROUTER.swapTo.selector,
            address(DAI),
            address(USDC),
            BASE_USER_DAI_BALANCE,
            address(GENIUS_ROUTER)
        );

        uint256 fee = 1 ether;
        uint256 minAmountOut = 49 ether;

        vm.startPrank(USER);

        DAI.approve(address(GENIUS_ROUTER), type(uint256).max);

        vm.expectEmit(address(GENIUS_VAULT));
        emit IGeniusVault.OrderCreated(
            bytes32(uint256(1)),
            RECEIVER,
            TOKEN_IN,
            BASE_ROUTER_USDC_BALANCE / 2,
            block.chainid,
            destChainId,
            block.timestamp + 200,
            fee
        );

        GENIUS_ROUTER.swapAndCreateOrder(
            bytes32(uint256(1)),
            tokensIn,
            amountsIn,
            address(DEX_ROUTER),
            data,
            USER,
            destChainId,
            block.timestamp + 200,
            fee,
            RECEIVER,
            minAmountOut,
            TOKEN_OUT
        );

        assertEq(
            USDC.balanceOf(address(GENIUS_VAULT)),
            BASE_ROUTER_USDC_BALANCE / 2
        );
    }

    function testSwapAndCreateOrderPermit2() public {
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
            DEX_ROUTER.swapTo.selector,
            address(DAI),
            address(USDC),
            BASE_USER_DAI_BALANCE,
            address(GENIUS_ROUTER)
        );

        uint256 fee = 1 ether;
        uint256 minAmountOut = 49 ether;

        vm.startPrank(USER);

        DAI.approve(address(GENIUS_ROUTER), type(uint256).max);

        vm.expectEmit(address(GENIUS_VAULT));
        emit IGeniusVault.OrderCreated(
            bytes32(uint256(1)),
            RECEIVER,
            TOKEN_IN,
            BASE_ROUTER_USDC_BALANCE / 2,
            block.chainid,
            destChainId,
            block.timestamp + 200,
            fee
        );

        GENIUS_ROUTER.swapAndCreateOrderPermit2(
            bytes32(uint256(1)),
            permitBatch,
            permitSignature,
            address(DEX_ROUTER),
            data,
            destChainId,
            block.timestamp + 200,
            fee,
            RECEIVER,
            minAmountOut,
            TOKEN_OUT
        );

        assertEq(
            USDC.balanceOf(address(GENIUS_VAULT)),
            BASE_ROUTER_USDC_BALANCE / 2
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
                spender: address(GENIUS_ROUTER),
                sigDeadline: 1900000000
            });

        bytes memory permitSignature = sigUtils.getPermitBatchSignature(
            permitBatch,
            USER_PK,
            DOMAIN_SEPERATOR
        );

        return (permitBatch, permitSignature);
    }

    function testSwapAndCreateOrderWithMultipleTokens() public {
        address[] memory tokensIn = new address[](2);
        uint256[] memory amountsIn = new uint256[](2);

        tokensIn[0] = address(DAI);
        tokensIn[1] = address(WETH);
        amountsIn[0] = BASE_USER_DAI_BALANCE / 2;
        amountsIn[1] = BASE_USER_WETH_BALANCE / 2;

        address[] memory targets = new address[](4);
        bytes[] memory data = new bytes[](4);
        uint256[] memory values = new uint256[](4);

        targets[0] = address(DAI);
        data[0] = abi.encodeWithSelector(
            DAI.approve.selector,
            address(DEX_ROUTER),
            BASE_USER_DAI_BALANCE / 2
        );
        targets[1] = address(DEX_ROUTER);
        data[1] = abi.encodeWithSelector(
            DEX_ROUTER.swapTo.selector,
            address(DAI),
            address(USDC),
            BASE_USER_DAI_BALANCE / 2,
            address(GENIUS_ROUTER)
        );
        targets[2] = address(WETH);
        data[2] = abi.encodeWithSelector(
            WETH.approve.selector,
            address(DEX_ROUTER),
            BASE_USER_WETH_BALANCE / 2
        );
        targets[3] = address(DEX_ROUTER);
        data[3] = abi.encodeWithSelector(
            DEX_ROUTER.swapTo.selector,
            address(WETH),
            address(USDC),
            BASE_USER_WETH_BALANCE / 2,
            address(GENIUS_ROUTER)
        );

        for (uint i = 0; i < 4; i++) {
            values[i] = 0;
        }

        uint256 fee = 1 ether;
        uint256 minAmountOut = 98 ether;

        vm.startPrank(USER);

        DAI.approve(address(GENIUS_ROUTER), type(uint256).max);
        WETH.approve(address(GENIUS_ROUTER), type(uint256).max);

        vm.expectEmit(address(GENIUS_VAULT));
        emit IGeniusVault.OrderCreated(
            bytes32(uint256(1)),
            RECEIVER,
            TOKEN_IN,
            (BASE_ROUTER_USDC_BALANCE * 75) / 100,
            block.chainid,
            destChainId,
            block.timestamp + 200,
            fee
        );

        bytes memory transactions = _encodeTransactions(targets, values, data);

        GENIUS_ROUTER.swapAndCreateOrder(
            bytes32(uint256(1)),
            tokensIn,
            amountsIn,
            address(PROXYCALL),
            transactions,
            USER,
            destChainId,
            block.timestamp + 200,
            fee,
            RECEIVER,
            minAmountOut,
            TOKEN_OUT
        );

        assertEq(
            USDC.balanceOf(address(GENIUS_VAULT)),
            (BASE_ROUTER_USDC_BALANCE * 75) / 100
        );
    }

    function testSwapAndCreateOrderWithInsufficientAllowance() public {
        address[] memory tokensIn = new address[](1);
        uint256[] memory amountsIn = new uint256[](1);

        tokensIn[0] = address(DAI);
        amountsIn[0] = BASE_USER_DAI_BALANCE;

        bytes memory data = abi.encodeWithSelector(
            DEX_ROUTER.swapTo.selector,
            address(DAI),
            address(USDC),
            BASE_USER_DAI_BALANCE,
            address(GENIUS_ROUTER)
        );
        uint256 fee = 1 ether;
        uint256 minAmountOut = 49 ether;

        vm.startPrank(USER);

        // Set insufficient allowance
        DAI.approve(address(GENIUS_ROUTER), BASE_USER_DAI_BALANCE / 2);

        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        GENIUS_ROUTER.swapAndCreateOrder(
            bytes32(uint256(1)),
            tokensIn,
            amountsIn,
            address(DEX_ROUTER),
            data,
            USER,
            destChainId,
            block.timestamp + 200,
            fee,
            RECEIVER,
            minAmountOut,
            TOKEN_OUT
        );
    }

    function testSwapAndCreateOrderWithExpiredDeadline() public {
        address[] memory tokensIn = new address[](1);
        uint256[] memory amountsIn = new uint256[](1);

        tokensIn[0] = address(DAI);
        amountsIn[0] = BASE_USER_DAI_BALANCE;

        bytes memory data = abi.encodeWithSelector(
            DEX_ROUTER.swapTo.selector,
            address(DAI),
            address(USDC),
            BASE_USER_DAI_BALANCE,
            address(GENIUS_ROUTER)
        );

        uint256 fee = 1 ether;
        uint256 minAmountOut = 49 ether;

        vm.startPrank(USER);

        DAI.approve(address(GENIUS_ROUTER), type(uint256).max);

        vm.expectRevert(
            abi.encodeWithSelector(GeniusErrors.InvalidDeadline.selector)
        );
        GENIUS_ROUTER.swapAndCreateOrder(
            bytes32(uint256(1)),
            tokensIn,
            amountsIn,
            address(DEX_ROUTER),
            data,
            USER,
            destChainId,
            block.timestamp - 1, // Expired deadline
            fee,
            RECEIVER,
            minAmountOut,
            TOKEN_OUT
        );
    }

    function testSwapAndCreateOrderWithZeroFee() public {
        address[] memory tokensIn = new address[](1);
        uint256[] memory amountsIn = new uint256[](1);

        tokensIn[0] = address(DAI);
        amountsIn[0] = BASE_USER_DAI_BALANCE;

        bytes memory data = abi.encodeWithSelector(
            DEX_ROUTER.swapTo.selector,
            address(DAI),
            address(USDC),
            BASE_USER_DAI_BALANCE,
            address(GENIUS_ROUTER)
        );

        uint256 fee = 0; // Zero fee
        uint256 minAmountOut = 49 ether;

        vm.startPrank(USER);

        DAI.approve(address(GENIUS_ROUTER), type(uint256).max);

        vm.expectEmit(address(GENIUS_VAULT));
        emit IGeniusVault.OrderCreated(
            bytes32(uint256(1)),
            RECEIVER,
            TOKEN_IN,
            BASE_ROUTER_USDC_BALANCE / 2,
            block.chainid,
            destChainId,
            block.timestamp + 200,
            fee
        );

        GENIUS_ROUTER.swapAndCreateOrder(
            bytes32(uint256(1)),
            tokensIn,
            amountsIn,
            address(DEX_ROUTER),
            data,
            USER,
            destChainId,
            block.timestamp + 200,
            fee,
            RECEIVER,
            minAmountOut,
            TOKEN_OUT
        );

        assertEq(
            USDC.balanceOf(address(GENIUS_VAULT)),
            BASE_ROUTER_USDC_BALANCE / 2
        );
    }

    function testSwapAndCreateOrderWithInvalidDestinationChain() public {
        address[] memory tokensIn = new address[](1);
        uint256[] memory amountsIn = new uint256[](1);

        tokensIn[0] = address(DAI);
        amountsIn[0] = BASE_USER_DAI_BALANCE;

        bytes memory data = abi.encodeWithSelector(
            DEX_ROUTER.swapTo.selector,
            address(DAI),
            address(USDC),
            BASE_USER_DAI_BALANCE,
            address(GENIUS_ROUTER)
        );

        uint256 fee = 1 ether;
        uint256 minAmountOut = 49 ether;

        vm.startPrank(USER);

        DAI.approve(address(GENIUS_ROUTER), type(uint256).max);

        vm.expectRevert(
            abi.encodeWithSelector(
                GeniusErrors.InvalidDestChainId.selector,
                block.chainid
            )
        );
        GENIUS_ROUTER.swapAndCreateOrder(
            bytes32(uint256(1)),
            tokensIn,
            amountsIn,
            address(DEX_ROUTER),
            data,
            USER,
            block.chainid, // Same as current chain ID
            block.timestamp + 200,
            fee,
            RECEIVER,
            minAmountOut,
            TOKEN_OUT
        );
    }

    function testSwapAndCreateOrderWithEmptyTargets() public {
        address[] memory tokensIn = new address[](1);
        uint256[] memory amountsIn = new uint256[](1);

        tokensIn[0] = address(DAI);
        amountsIn[0] = BASE_USER_DAI_BALANCE;

        uint256 fee = 1 ether;
        uint256 minAmountOut = 49 ether;

        vm.startPrank(USER);

        DAI.approve(address(GENIUS_ROUTER), type(uint256).max);

        vm.expectRevert(
            abi.encodeWithSelector(GeniusErrors.NonAddress0.selector)
        );
        GENIUS_ROUTER.swapAndCreateOrder(
            bytes32(uint256(1)),
            tokensIn,
            amountsIn,
            address(0),
            "",
            USER,
            destChainId,
            block.timestamp + 200,
            fee,
            RECEIVER,
            minAmountOut,
            TOKEN_OUT
        );
    }

    function testSwapAndCreateOrderWithMismatchedArrayLengths() public {
        address[] memory tokensIn = new address[](1);
        uint256[] memory amountsIn = new uint256[](0);

        tokensIn[0] = address(DAI);

        bytes memory data = abi.encodeWithSelector(
            DAI.approve.selector,
            address(DEX_ROUTER),
            BASE_USER_DAI_BALANCE
        );

        uint256 fee = 1 ether;
        uint256 minAmountOut = 49 ether;

        vm.startPrank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(GeniusErrors.ArrayLengthsMismatch.selector)
        );
        GENIUS_ROUTER.swapAndCreateOrder(
            bytes32(uint256(1)),
            tokensIn,
            amountsIn,
            address(DEX_ROUTER),
            data,
            USER,
            destChainId,
            block.timestamp + 200,
            fee,
            RECEIVER,
            minAmountOut,
            TOKEN_OUT
        );
    }

    function testSwapAndCreateOrderWithInvalidReceiver() public {
        address[] memory tokensIn = new address[](1);
        uint256[] memory amountsIn = new uint256[](1);

        tokensIn[0] = address(DAI);
        amountsIn[0] = BASE_USER_DAI_BALANCE;

        bytes memory data = abi.encodeWithSelector(
            DEX_ROUTER.swapTo.selector,
            address(DAI),
            address(USDC),
            BASE_USER_DAI_BALANCE,
            address(GENIUS_ROUTER)
        );

        uint256 fee = 1 ether;
        uint256 minAmountOut = 49 ether;

        vm.startPrank(USER);

        DAI.approve(address(GENIUS_ROUTER), type(uint256).max);

        vm.expectRevert(
            abi.encodeWithSelector(GeniusErrors.NonAddress0.selector)
        );
        GENIUS_ROUTER.swapAndCreateOrder(
            bytes32(uint256(1)),
            tokensIn,
            amountsIn,
            address(DEX_ROUTER),
            data,
            USER,
            destChainId,
            block.timestamp + 200,
            fee,
            bytes32(0), // Invalid receiver
            minAmountOut,
            TOKEN_OUT
        );
    }

    function testSwapAndCreateOrderWithInvalidTokenOut() public {
        address[] memory tokensIn = new address[](1);
        uint256[] memory amountsIn = new uint256[](1);

        tokensIn[0] = address(DAI);
        amountsIn[0] = BASE_USER_DAI_BALANCE;

        bytes memory data = abi.encodeWithSelector(
            DEX_ROUTER.swapTo.selector,
            address(DAI),
            address(USDC),
            BASE_USER_DAI_BALANCE,
            address(GENIUS_ROUTER)
        );

        uint256 fee = 1 ether;
        uint256 minAmountOut = 49 ether;

        vm.startPrank(USER);

        DAI.approve(address(GENIUS_ROUTER), type(uint256).max);

        vm.expectRevert(
            abi.encodeWithSelector(GeniusErrors.NonAddress0.selector)
        );
        GENIUS_ROUTER.swapAndCreateOrder(
            bytes32(uint256(1)),
            tokensIn,
            amountsIn,
            address(DEX_ROUTER),
            data,
            USER,
            destChainId,
            block.timestamp + 200,
            fee,
            RECEIVER,
            minAmountOut,
            bytes32(0) // Invalid tokenOut
        );
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
