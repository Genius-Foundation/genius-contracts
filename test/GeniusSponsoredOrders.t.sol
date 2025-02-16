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
import {IGeniusGasTank} from "../src/interfaces/IGeniusGasTank.sol";
import {GeniusGasTank} from "../src/GeniusGasTank.sol";
import {MockV3Aggregator} from "./mocks/MockV3Aggregator.sol";

contract GeniusSponsoredOrdersTest is Test {
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
    GeniusGasTank public GAS_TANK;

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
        MOCK_PRICE_FEED = new MockV3Aggregator(INITIAL_STABLECOIN_PRICE);
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
        GENIUS_ROUTER = new GeniusRouter(
            address(PERMIT2),
            address(GENIUS_VAULT),
            address(PROXYCALL)
        );

        RECEIVER = GENIUS_VAULT.addressToBytes32(USER);
        TOKEN_OUT = GENIUS_VAULT.addressToBytes32(address(USDC));
        TOKEN_IN = TOKEN_OUT;

        GAS_TANK = new GeniusGasTank(
            ADMIN,
            payable(FEE_RECIPIENT),
            address(PERMIT2),
            address(PROXYCALL)
        );

        vm.startPrank(ADMIN);

        PROXYCALL.grantRole(PROXYCALL.CALLER_ROLE(), address(GENIUS_ROUTER));
        PROXYCALL.grantRole(PROXYCALL.CALLER_ROLE(), address(GENIUS_VAULT));
        PROXYCALL.grantRole(PROXYCALL.CALLER_ROLE(), address(GAS_TANK));
        GENIUS_VAULT.setTargetChainMinFee(address(USDC), destChainId, 1 ether);

        vm.stopPrank();

        deal(address(USDC), address(DEX_ROUTER), BASE_ROUTER_USDC_BALANCE);
        deal(address(DAI), USER, BASE_USER_DAI_BALANCE);
        deal(address(WETH), USER, BASE_USER_WETH_BALANCE);

        vm.startPrank(USER);
        USDC.approve(address(PERMIT2), type(uint256).max);
        DAI.approve(address(PERMIT2), type(uint256).max);
        vm.stopPrank();
    }

    function testSponsorOrderCreation() public {
        uint256 sponsorFee = 2 ether;

        address[] memory tokensIn = new address[](1);
        uint256[] memory amountsIn = new uint256[](1);

        tokensIn[0] = address(DAI);
        amountsIn[0] = BASE_USER_DAI_BALANCE - sponsorFee;

        bytes memory data = abi.encodeWithSelector(
            DEX_ROUTER.swapTo.selector,
            address(DAI),
            address(USDC),
            BASE_USER_DAI_BALANCE - sponsorFee,
            address(GENIUS_ROUTER)
        );

        uint256 bridgeFee = 1 ether;
        uint256 minAmountOut = 49 ether;

        bytes memory gasTankData = abi.encodeWithSelector(
            GENIUS_ROUTER.swapAndCreateOrder.selector,
            bytes32(uint256(1)),
            tokensIn,
            amountsIn,
            address(DEX_ROUTER),
            address(DEX_ROUTER),
            data,
            USER,
            destChainId,
            bridgeFee,
            RECEIVER,
            minAmountOut,
            TOKEN_OUT
        );

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

        bytes memory sponsorSignature = _generateSignature(
            address(GENIUS_ROUTER),
            gasTankData,
            permitBatch,
            GAS_TANK.nonces(USER),
            address(DAI),
            sponsorFee,
            1900000000,
            USER_PK
        );

        IGeniusVault.Order memory order = IGeniusVault.Order({
            seed: bytes32(uint256(1)),
            trader: RECEIVER,
            receiver: RECEIVER,
            tokenIn: TOKEN_IN,
            tokenOut: TOKEN_OUT,
            amountIn: BASE_ROUTER_USDC_BALANCE / 2,
            minAmountOut: minAmountOut,
            destChainId: destChainId,
            srcChainId: block.chainid,
            fee: bridgeFee
        });

        vm.startPrank(SENDER);

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
            bridgeFee
        );

        vm.expectEmit(address(GAS_TANK));
        emit IGeniusGasTank.OrderedTransactionsSponsored(
            SENDER,
            USER,
            address(GENIUS_ROUTER),
            address(DAI),
            sponsorFee,
            0
        );

        GAS_TANK.sponsorOrderedTransactions(
            address(GENIUS_ROUTER),
            gasTankData,
            permitBatch,
            permitSignature,
            USER,
            address(DAI),
            sponsorFee,
            1900000000,
            sponsorSignature
        );

        vm.stopPrank();

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
                block.chainid,
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
}
