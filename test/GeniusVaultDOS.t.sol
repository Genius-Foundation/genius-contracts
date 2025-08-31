// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import {Test, console} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {MockDEXRouter} from "./mocks/MockDEXRouter.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

import {GeniusVault} from "../src/GeniusVault.sol";
import {GeniusProxyCall} from "../src/GeniusProxyCall.sol";
import {GeniusErrors} from "../src/libs/GeniusErrors.sol";
import {MockV3Aggregator} from "./mocks/MockV3Aggregator.sol";

contract GeniusVaultDOSTest is Test {
    int256 public constant INITIAL_STABLECOIN_PRICE = 100_000_000;
    MockV3Aggregator public MOCK_PRICE_FEED;

    uint256 avalanche;
    uint16 constant targetChainId = 42;
    string private rpc = vm.envString("AVALANCHE_RPC_URL");

    address OWNER;
    address TRADER;
    address ORCHESTRATOR;
    address public BRIDGE;
    address PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    address public constant NATIVE = address(0);
    ERC20 public TOKEN1;
    ERC20 public TOKEN2;
    ERC20 public TOKEN3;

    ERC20 public USDC;
    GeniusVault public VAULT;
    GeniusProxyCall public PROXYCALL;
    MockDEXRouter public DEX_ROUTER;

    function setUp() public {
        avalanche = vm.createFork(rpc);
        vm.selectFork(avalanche);
        assertEq(vm.activeFork(), avalanche);

        USDC = ERC20(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E); // USDC on Avalanche

        OWNER = makeAddr("OWNER");
        TRADER = makeAddr("TRADER");
        ORCHESTRATOR = makeAddr("ORCHESTRATOR");

        MOCK_PRICE_FEED = new MockV3Aggregator(INITIAL_STABLECOIN_PRICE);
        DEX_ROUTER = new MockDEXRouter();
        BRIDGE = makeAddr("BRIDGE");

        // Deploy mock tokens
        TOKEN1 = new MockERC20("Token1", "TK1", 18);
        TOKEN2 = new MockERC20("Token2", "TK2", 18);
        TOKEN3 = new MockERC20("Token3", "TK3", 18);

        // Initialize vault with supported tokens
        address[] memory supportedTokens = new address[](4);
        supportedTokens[0] = NATIVE;
        supportedTokens[1] = address(TOKEN1);
        supportedTokens[2] = address(TOKEN2);
        supportedTokens[3] = address(TOKEN3);

        address[] memory bridges = new address[](1);
        bridges[0] = address(DEX_ROUTER);

        address[] memory routers = new address[](1);
        routers[0] = address(DEX_ROUTER);

        // Deploy proxy call implementation and proxy
        GeniusProxyCall proxyCallImpl = new GeniusProxyCall();
        bytes memory proxyCallInitData = abi.encodeWithSelector(
            GeniusProxyCall.initialize.selector,
            OWNER,
            new address[](0)
        );
        ERC1967Proxy proxyCallProxy = new ERC1967Proxy(
            address(proxyCallImpl),
            proxyCallInitData
        );
        PROXYCALL = GeniusProxyCall(payable(address(proxyCallProxy)));

        vm.startPrank(OWNER);
        GeniusVault implementation = new GeniusVault();

        bytes memory data = abi.encodeWithSelector(
            GeniusVault.initialize.selector,
            address(USDC),
            OWNER,
            address(PROXYCALL),
            7_500,
            address(MOCK_PRICE_FEED),
            86_000,
            99_000_000,
            101_000_000,
            1000 ether
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);

        VAULT = GeniusVault(address(proxy));

        VAULT.grantRole(VAULT.ORCHESTRATOR_ROLE(), ORCHESTRATOR);

        PROXYCALL.grantRole(PROXYCALL.CALLER_ROLE(), address(VAULT));

        vm.stopPrank();

        deal(address(USDC), ORCHESTRATOR, 1000 ether);
    }

    function testDOSAttackOnRemoveBridgeLiquidity() public {
        // Add initial liquidity
        vm.startPrank(ORCHESTRATOR);
        USDC.transfer(address(VAULT), 500 ether);
        vm.stopPrank();

        // Simulate a donation to the vault
        deal(address(USDC), address(VAULT), 600 ether);

        // Prepare removal of bridge liquidity
        vm.startPrank(ORCHESTRATOR);

        address recipient = makeAddr("recipient");
        uint256 amountToRemove = 500 ether;

        bytes memory transferData = abi.encodeWithSelector(
            USDC.transfer.selector,
            recipient,
            amountToRemove
        );

        // This should not revert
        VAULT.rebalanceLiquidity(
            amountToRemove,
            targetChainId,
            address(USDC),
            transferData
        );

        vm.stopPrank();

        // Verify that the funds have been transferred
        assertEq(USDC.balanceOf(recipient), amountToRemove);
    }
}
