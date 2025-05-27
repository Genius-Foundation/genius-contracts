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
import {MockV3Aggregator} from "./mocks/MockV3Aggregator.sol";
import {FeeCollector} from "../src/fees/FeeCollector.sol";
import {IFeeCollector} from "../src/interfaces/IFeeCollector.sol";

contract GeniusRouterTest is Test {
    int256 public constant INITIAL_STABLECOIN_PRICE = 100_000_000;
    MockV3Aggregator public MOCK_PRICE_FEED;

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
    FeeCollector public FEE_COLLECTOR;

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

        MOCK_PRICE_FEED = new MockV3Aggregator(INITIAL_STABLECOIN_PRICE);
        DEX_ROUTER = new MockDEXRouter();
        PERMIT2 = IEIP712(0x000000000022D473030F116dDEE9F6B43aC78BA3);
        DOMAIN_SEPERATOR = PERMIT2.DOMAIN_SEPARATOR();

        PROXYCALL = new GeniusProxyCall(ADMIN, new address[](0));
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
            address(MOCK_PRICE_FEED),
            86_000,
            99_000_000,
            101_000_000,
            1000 ether
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);

        GENIUS_VAULT = GeniusVault(address(proxy));
        // Deploy FeeCollector
        FeeCollector feeCollectorImplementation = new FeeCollector();

        bytes memory feeCollectorData = abi.encodeWithSelector(
            FeeCollector.initialize.selector,
            ADMIN,
            address(USDC),
            2000, // 20% to protocol
            ADMIN,
            ADMIN,
            ADMIN
        );

        ERC1967Proxy feeCollectorProxy = new ERC1967Proxy(
            address(feeCollectorImplementation),
            feeCollectorData
        );

        FEE_COLLECTOR = FeeCollector(address(feeCollectorProxy));

        // Set FeeCollector in vault
        GENIUS_VAULT.setFeeCollector(address(FEE_COLLECTOR));

        // Set vault in FeeCollector
        FEE_COLLECTOR.setVault(address(GENIUS_VAULT));

        // Set up fee tiers in FeeCollector
        uint256[] memory thresholdAmounts = new uint256[](3);
        thresholdAmounts[0] = 0;
        thresholdAmounts[1] = 100 ether;
        thresholdAmounts[2] = 500 ether;

        uint256[] memory bpsFees = new uint256[](3);
        bpsFees[0] = 30; // 0.3%
        bpsFees[1] = 20; // 0.2%
        bpsFees[2] = 10; // 0.1%

        FEE_COLLECTOR.setFeeTiers(thresholdAmounts, bpsFees);

        // Set up insurance fee tiers
        uint256[] memory insThresholdAmounts = new uint256[](3);
        insThresholdAmounts[0] = 0;
        insThresholdAmounts[1] = 100 ether;
        insThresholdAmounts[2] = 500 ether;

        uint256[] memory insBpsFees = new uint256[](3);
        insBpsFees[0] = 30; // 0.3%
        insBpsFees[1] = 20; // 0.2%
        insBpsFees[2] = 10; // 0.1%

        FEE_COLLECTOR.setInsuranceFeeTiers(insThresholdAmounts, insBpsFees);

        // Set min fee in FeeCollector
        FEE_COLLECTOR.setTargetChainMinFee(destChainId, 1 ether);

        // Set decimals in Vault
        GENIUS_VAULT.setChainStablecoinDecimals(destChainId, 6);

        GENIUS_ROUTER = new GeniusRouter(
            address(PERMIT2),
            address(GENIUS_VAULT),
            address(PROXYCALL),
            address(FEE_COLLECTOR)
        );

        PROXYCALL.grantRole(PROXYCALL.CALLER_ROLE(), address(GENIUS_ROUTER));
        PROXYCALL.grantRole(PROXYCALL.CALLER_ROLE(), address(GENIUS_VAULT));

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

        // Use correct fee based on actual calculation (baseFee + bpsFee + insuranceFee)
        uint256 fee = FEE_COLLECTOR
            .getOrderFees(BASE_ROUTER_USDC_BALANCE / 2, destChainId)
            .totalFee; // 1.3 ether
        uint256 minAmountOut = 49 ether;

        IGeniusVault.Order memory order = IGeniusVault.Order({
            seed: bytes32(uint256(1)),
            trader: RECEIVER,
            receiver: RECEIVER,
            amountIn: BASE_ROUTER_USDC_BALANCE / 2,
            tokenIn: TOKEN_IN,
            tokenOut: TOKEN_OUT,
            destChainId: destChainId,
            srcChainId: block.chainid,
            minAmountOut: minAmountOut,
            fee: fee
        });

        vm.startPrank(USER);

        DAI.approve(address(GENIUS_ROUTER), type(uint256).max);

        vm.expectEmit(address(GENIUS_VAULT));
        emit IGeniusVault.OrderCreated(
            destChainId,
            RECEIVER,
            RECEIVER,
            bytes32(uint256(1)),
            GENIUS_VAULT.orderHash(order),
            TOKEN_IN,
            TOKEN_OUT,
            BASE_ROUTER_USDC_BALANCE / 2,
            minAmountOut,
            fee
        );

        GENIUS_ROUTER.swapAndCreateOrder(
            bytes32(uint256(1)),
            tokensIn,
            amountsIn,
            address(DEX_ROUTER),
            address(DEX_ROUTER),
            data,
            USER,
            destChainId,
            0, // No fee surplus
            RECEIVER,
            minAmountOut,
            TOKEN_OUT
        );

        // Account for fee distribution - vault keeps insurance fee
        uint256 expectedVaultBalance = BASE_ROUTER_USDC_BALANCE /
            2 -
            fee +
            0.15 ether; // amountIn - (fee - insuranceFee)
        assertEq(USDC.balanceOf(address(GENIUS_VAULT)), expectedVaultBalance);
    }

    function testSwapAndCreateOrderWithFeeSurplus() public {
        address[] memory tokensIn = new address[](1);
        uint256[] memory amountsIn = new uint256[](1);

        tokensIn[0] = address(DAI);
        amountsIn[0] = BASE_USER_DAI_BALANCE;

        uint256 feeSurplus = 0.5 ether; // Example fee surplus

        bytes memory data = abi.encodeWithSelector(
            DEX_ROUTER.swapTo.selector,
            address(DAI),
            address(USDC),
            BASE_USER_DAI_BALANCE,
            address(GENIUS_ROUTER)
        );

        // Use correct fee based on actual calculation (baseFee + bpsFee + insuranceFee + feeSurplus)
        IFeeCollector.FeeBreakdown memory feeBreakdown = FEE_COLLECTOR
            .getOrderFees(BASE_ROUTER_USDC_BALANCE / 2, destChainId);

        uint256 fee = feeBreakdown.totalFee + feeSurplus;
        uint256 minAmountOut = 49 ether;

        IGeniusVault.Order memory order = IGeniusVault.Order({
            seed: bytes32(uint256(1)),
            trader: RECEIVER,
            receiver: RECEIVER,
            amountIn: BASE_ROUTER_USDC_BALANCE / 2,
            tokenIn: TOKEN_IN,
            tokenOut: TOKEN_OUT,
            destChainId: destChainId,
            srcChainId: block.chainid,
            minAmountOut: minAmountOut,
            fee: fee
        });

        vm.startPrank(USER);

        DAI.approve(address(GENIUS_ROUTER), type(uint256).max);

        vm.expectEmit(address(GENIUS_VAULT));
        emit IGeniusVault.OrderCreated(
            destChainId,
            RECEIVER,
            RECEIVER,
            bytes32(uint256(1)),
            GENIUS_VAULT.orderHash(order),
            TOKEN_IN,
            TOKEN_OUT,
            BASE_ROUTER_USDC_BALANCE / 2,
            minAmountOut,
            fee
        );

        GENIUS_ROUTER.swapAndCreateOrder(
            bytes32(uint256(1)),
            tokensIn,
            amountsIn,
            address(DEX_ROUTER),
            address(DEX_ROUTER),
            data,
            USER,
            destChainId,
            feeSurplus,
            RECEIVER,
            minAmountOut,
            TOKEN_OUT
        );

        // Account for fee distribution - vault keeps insurance fee
        uint256 expectedVaultBalance = BASE_ROUTER_USDC_BALANCE /
            2 -
            fee +
            feeBreakdown.insuranceFee;
        assertEq(USDC.balanceOf(address(GENIUS_VAULT)), expectedVaultBalance);
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

        // Use correct fee based on actual calculation (baseFee + bpsFee + insuranceFee)
        uint256 fee = FEE_COLLECTOR
            .getOrderFees(BASE_ROUTER_USDC_BALANCE / 2, destChainId)
            .totalFee; // 1.3 ether
        uint256 minAmountOut = 49 ether;

        vm.startPrank(USER);

        DAI.approve(address(GENIUS_ROUTER), type(uint256).max);

        IGeniusVault.Order memory order = IGeniusVault.Order({
            seed: bytes32(uint256(1)),
            trader: RECEIVER,
            receiver: RECEIVER,
            amountIn: BASE_ROUTER_USDC_BALANCE / 2,
            tokenIn: TOKEN_IN,
            tokenOut: TOKEN_OUT,
            destChainId: destChainId,
            srcChainId: block.chainid,
            minAmountOut: minAmountOut,
            fee: fee
        });

        vm.expectEmit(address(GENIUS_VAULT));
        emit IGeniusVault.OrderCreated(
            destChainId,
            RECEIVER,
            RECEIVER,
            bytes32(uint256(1)),
            GENIUS_VAULT.orderHash(order),
            TOKEN_IN,
            TOKEN_OUT,
            BASE_ROUTER_USDC_BALANCE / 2,
            minAmountOut,
            fee
        );

        GENIUS_ROUTER.swapAndCreateOrderPermit2(
            bytes32(uint256(1)),
            permitBatch,
            permitSignature,
            address(DEX_ROUTER),
            address(DEX_ROUTER),
            data,
            destChainId,
            0, // No fee surplus
            RECEIVER,
            minAmountOut,
            TOKEN_OUT
        );

        // Account for fee distribution - vault keeps insurance fee
        uint256 expectedVaultBalance = BASE_ROUTER_USDC_BALANCE /
            2 -
            fee +
            0.15 ether; // amountIn - (fee - insuranceFee)
        assertEq(USDC.balanceOf(address(GENIUS_VAULT)), expectedVaultBalance);
    }

    function testSwapAndCreateOrderPermit2WithFeeSurplus() public {
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

        uint256 feeSurplus = 0.5 ether; // Example fee surplus

        IFeeCollector.FeeBreakdown memory feeBreakdown = FEE_COLLECTOR
            .getOrderFees(BASE_ROUTER_USDC_BALANCE / 2, destChainId);

        // Use correct fee based on actual calculation (baseFee + bpsFee + insuranceFee)
        uint256 fee = feeBreakdown.totalFee + feeSurplus;
        uint256 minAmountOut = 49 ether;

        vm.startPrank(USER);

        DAI.approve(address(GENIUS_ROUTER), type(uint256).max);

        IGeniusVault.Order memory order = IGeniusVault.Order({
            seed: bytes32(uint256(1)),
            trader: RECEIVER,
            receiver: RECEIVER,
            amountIn: BASE_ROUTER_USDC_BALANCE / 2,
            tokenIn: TOKEN_IN,
            tokenOut: TOKEN_OUT,
            destChainId: destChainId,
            srcChainId: block.chainid,
            minAmountOut: minAmountOut,
            fee: fee
        });

        vm.expectEmit(address(GENIUS_VAULT));
        emit IGeniusVault.OrderCreated(
            destChainId,
            RECEIVER,
            RECEIVER,
            bytes32(uint256(1)),
            GENIUS_VAULT.orderHash(order),
            TOKEN_IN,
            TOKEN_OUT,
            BASE_ROUTER_USDC_BALANCE / 2,
            minAmountOut,
            fee
        );

        GENIUS_ROUTER.swapAndCreateOrderPermit2(
            bytes32(uint256(1)),
            permitBatch,
            permitSignature,
            address(DEX_ROUTER),
            address(DEX_ROUTER),
            data,
            destChainId,
            feeSurplus,
            RECEIVER,
            minAmountOut,
            TOKEN_OUT
        );

        // Account for fee distribution - vault keeps insurance fee
        uint256 expectedVaultBalance = BASE_ROUTER_USDC_BALANCE /
            2 -
            fee +
            feeBreakdown.insuranceFee; // insurance fee is kept by vault
        assertEq(USDC.balanceOf(address(GENIUS_VAULT)), expectedVaultBalance);
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

        // Use correct fee based on actual calculation (baseFee + bpsFee + insuranceFee)
        uint256 fee = FEE_COLLECTOR
            .getOrderFees((BASE_ROUTER_USDC_BALANCE * 75) / 100, destChainId)
            .totalFee; // 1.45 ether
        uint256 minAmountOut = 98 ether;

        vm.startPrank(USER);

        DAI.approve(address(GENIUS_ROUTER), type(uint256).max);
        WETH.approve(address(GENIUS_ROUTER), type(uint256).max);

        IGeniusVault.Order memory order = IGeniusVault.Order({
            seed: bytes32(uint256(1)),
            trader: RECEIVER,
            receiver: RECEIVER,
            amountIn: (BASE_ROUTER_USDC_BALANCE * 75) / 100,
            tokenIn: TOKEN_IN,
            tokenOut: TOKEN_OUT,
            destChainId: destChainId,
            srcChainId: block.chainid,
            minAmountOut: minAmountOut,
            fee: fee
        });

        vm.expectEmit(address(GENIUS_VAULT));
        emit IGeniusVault.OrderCreated(
            destChainId,
            RECEIVER,
            RECEIVER,
            bytes32(uint256(1)),
            GENIUS_VAULT.orderHash(order),
            TOKEN_IN,
            TOKEN_OUT,
            (BASE_ROUTER_USDC_BALANCE * 75) / 100,
            minAmountOut,
            fee
        );

        bytes memory transactions = _encodeTransactions(targets, values, data);

        GENIUS_ROUTER.swapAndCreateOrder(
            bytes32(uint256(1)),
            tokensIn,
            amountsIn,
            address(PROXYCALL),
            address(PROXYCALL),
            transactions,
            USER,
            destChainId,
            0, // No fee surplus
            RECEIVER,
            minAmountOut,
            TOKEN_OUT
        );

        // Account for fee distribution - vault keeps insurance fee
        uint256 expectedVaultBalance = (BASE_ROUTER_USDC_BALANCE * 75) /
            100 -
            fee +
            0.225 ether; // amountIn - (fee - insuranceFee)
        assertEq(USDC.balanceOf(address(GENIUS_VAULT)), expectedVaultBalance);
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
            address(DEX_ROUTER),
            data,
            USER,
            destChainId,
            0, // No fee surplus
            RECEIVER,
            minAmountOut,
            TOKEN_OUT
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
            address(DEX_ROUTER),
            data,
            USER,
            block.chainid, // Same as current chain ID
            0, // No fee surplus
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
            address(0),
            "",
            USER,
            destChainId,
            0, // No fee surplus
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
            address(DEX_ROUTER),
            data,
            USER,
            destChainId,
            0, // No fee surplus
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
            address(DEX_ROUTER),
            data,
            USER,
            destChainId,
            0, // No fee surplus
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
            address(DEX_ROUTER),
            data,
            USER,
            destChainId,
            0, // No fee surplus
            RECEIVER,
            minAmountOut,
            bytes32(0) // Invalid tokenOut
        );
    }

    function testSwapAndCreateOrderWithEth() public {
        // Setup empty arrays since we're using ETH
        address[] memory tokensIn = new address[](0);
        uint256[] memory amountsIn = new uint256[](0);

        uint256 ethAmount = 1 ether;

        // Create swap data for DEX router to swap ETH to USDC
        bytes memory data = abi.encodeWithSelector(
            DEX_ROUTER.swapETHToToken.selector,
            address(USDC),
            address(GENIUS_ROUTER)
        );

        // Use correct fee based on actual calculation (baseFee + bpsFee + insuranceFee)
        uint256 fee = FEE_COLLECTOR
            .getOrderFees(BASE_ROUTER_USDC_BALANCE / 2, destChainId)
            .totalFee; // 1.3 ether
        uint256 minAmountOut = 49 ether;

        vm.deal(USER, ethAmount); // Give USER some ETH
        vm.startPrank(USER);

        IGeniusVault.Order memory order = IGeniusVault.Order({
            seed: bytes32(uint256(1)),
            trader: RECEIVER,
            receiver: RECEIVER,
            amountIn: BASE_ROUTER_USDC_BALANCE / 2,
            tokenIn: TOKEN_IN,
            tokenOut: TOKEN_OUT,
            destChainId: destChainId,
            srcChainId: block.chainid,
            minAmountOut: minAmountOut,
            fee: fee
        });

        vm.expectEmit(address(GENIUS_VAULT));
        emit IGeniusVault.OrderCreated(
            destChainId,
            RECEIVER,
            RECEIVER,
            bytes32(uint256(1)),
            GENIUS_VAULT.orderHash(order),
            TOKEN_IN,
            TOKEN_OUT,
            BASE_ROUTER_USDC_BALANCE / 2,
            minAmountOut,
            fee
        );

        // Call swapAndCreateOrder with ETH value
        GENIUS_ROUTER.swapAndCreateOrder{value: ethAmount}(
            bytes32(uint256(1)),
            tokensIn,
            amountsIn,
            address(DEX_ROUTER),
            address(DEX_ROUTER),
            data,
            USER,
            destChainId,
            0, // No fee surplus
            RECEIVER,
            minAmountOut,
            TOKEN_OUT
        );

        // Verify USDC was received and deposited in vault
        // Account for fee distribution - vault keeps insurance fee
        uint256 expectedVaultBalance = BASE_ROUTER_USDC_BALANCE /
            2 -
            fee +
            0.15 ether; // amountIn - (fee - insuranceFee)
        assertEq(USDC.balanceOf(address(GENIUS_VAULT)), expectedVaultBalance);

        // Verify ETH was spent
        assertEq(address(USER).balance, 0);
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
