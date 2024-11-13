// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/GeniusVault.sol";
import {IGeniusVault} from "../../src/interfaces/IGeniusVault.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {GeniusProxyCall} from "../../src/GeniusProxyCall.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MockStablecoin is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {
        _mint(msg.sender, 1_000_000_000e18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract GeniusVaultHandler is Test {
    GeniusVault public vault;
    ERC20 public USDC;
    GeniusProxyCall public proxyCall;

    // Ghost variables for state tracking
    uint256 public totalOrdersCreated;
    uint256 public totalOrdersFilled;
    uint256 public totalFeesCollected;
    uint256 public totalFeesClaimed;
    uint256 public totalStaked;

    // Add sequence control
    uint256 public constant MAX_OPERATIONS = 100;
    uint256 public operationCount;

    mapping(bytes32 => bool) public knownOrders;
    mapping(address => uint256) public userStakes;
    mapping(bytes32 => IGeniusVault.OrderStatus) public expectedOrderStatus;

    // Constants with reasonable bounds
    uint256 public constant INITIAL_BALANCE = 1_000 ether;
    uint256 public constant MAX_STAKE_AMOUNT = 10_000 ether;
    uint256 public constant MAX_ORDER_AMOUNT = 1_000 ether;
    uint256 public constant NUM_ACTORS = 5;

    // Actor addresses
    address[] public actors;

    constructor(
        GeniusVault _vault,
        ERC20 _USDC,
        GeniusProxyCall _proxyCall,
        address _owner,
        address _orchestrator
    ) {
        vault = _vault;
        USDC = _USDC;
        proxyCall = _proxyCall;

        // Setup test actors
        for (uint256 i = 0; i < NUM_ACTORS; i++) {
            address actor = makeAddr(string.concat("actor", vm.toString(i)));
            actors.push(actor);
            deal(address(USDC), actor, INITIAL_BALANCE);
            vm.prank(actor);
            USDC.approve(address(vault), type(uint256).max);
        }
    }

    modifier useActor(uint256 actorSeed) {
        address actor = actors[bound(actorSeed, 0, actors.length - 1)];
        vm.startPrank(actor);
        _;
        vm.stopPrank();
    }

    // Add sequence control to all operations
    modifier controlledOperation() {
        if (operationCount >= MAX_OPERATIONS) return;
        operationCount++;
        _;
    }

    function stake(
        uint256 amount,
        uint256 actorSeed
    ) external useActor(actorSeed) controlledOperation {
        // Bound the stake amount to prevent unrealistic values
        amount = bound(amount, 1e18, MAX_STAKE_AMOUNT);
        address actor = actors[bound(actorSeed, 0, actors.length - 1)];

        // Check if actor has enough balance
        uint256 balance = USDC.balanceOf(actor);
        if (balance < amount) return;

        try vault.stakeDeposit(amount, actor) {
            totalStaked += amount;
            userStakes[actor] += amount;
        } catch {}
    }

    function withdraw(
        uint256 amount,
        uint256 actorSeed
    ) external useActor(actorSeed) controlledOperation {
        address actor = actors[bound(actorSeed, 0, actors.length - 1)];
        uint256 actorBalance = vault.balanceOf(actor);
        if (actorBalance == 0) return;

        amount = bound(amount, 1, actorBalance);

        try vault.stakeWithdraw(amount, actor, actor) {
            totalStaked -= amount;
            userStakes[actor] -= amount;
        } catch {}
    }

    function createOrder(
        uint256 amountInSeed,
        uint256 minAmountOutSeed,
        uint256 feeSeed,
        uint256 actorSeed,
        uint256 destChainIdSeed
    ) external useActor(actorSeed) controlledOperation {
        // Bound inputs to reasonable values
        uint256 amountIn = bound(amountInSeed, 1e18, MAX_ORDER_AMOUNT);
        uint256 fee = bound(feeSeed, 1e18, amountIn / 10);
        uint256 destChainId = bound(destChainIdSeed, 1, 100);
        if (destChainId == block.chainid) destChainId++;

        address actor = actors[bound(actorSeed, 0, actors.length - 1)];

        // Check if actor has enough balance
        uint256 balance = USDC.balanceOf(actor);
        if (balance < amountIn) return;

        IGeniusVault.Order memory order = IGeniusVault.Order({
            seed: keccak256(abi.encodePacked(block.timestamp, actor)),
            trader: vault.addressToBytes32(actor),
            receiver: vault.addressToBytes32(actor),
            tokenIn: vault.addressToBytes32(address(USDC)),
            tokenOut: vault.addressToBytes32(address(USDC)),
            amountIn: amountIn,
            minAmountOut: bound(minAmountOutSeed, 1, amountIn),
            srcChainId: block.chainid,
            destChainId: destChainId,
            fee: fee
        });

        bytes32 orderHash = vault.orderHash(order);
        if (knownOrders[orderHash]) return;

        try vault.createOrder(order) {
            knownOrders[orderHash] = true;
            expectedOrderStatus[orderHash] = IGeniusVault.OrderStatus.Created;
            totalOrdersCreated++;
            totalFeesCollected += fee;
        } catch {}
    }

    function fillOrder(
        bytes32 orderHash,
        uint256 actorSeed
    ) external useActor(actorSeed) {
        if (
            !knownOrders[orderHash] ||
            expectedOrderStatus[orderHash] != IGeniusVault.OrderStatus.Created
        ) return;

        // Mock fill order parameters
        IGeniusVault.Order memory order;
        order.amountIn = 1e18; // Simplified for testing
        order.fee = 0.1e18;
        order.destChainId = block.chainid;

        try vault.fillOrder(order, address(0), "", address(0), "") {
            expectedOrderStatus[orderHash] = IGeniusVault.OrderStatus.Filled;
            totalOrdersFilled++;
        } catch {}
    }

    function claimFees(
        uint256 amountSeed,
        uint256 actorSeed
    ) external useActor(actorSeed) {
        uint256 claimable = vault.claimableFees();
        if (claimable == 0) return;

        uint256 amount = bound(amountSeed, 1, claimable);

        try vault.claimFees(amount, address(USDC)) {
            totalFeesClaimed += amount;
        } catch {}
    }

    // Add a function to reset the operation count for new test runs
    function resetOperationCount() external {
        operationCount = 0;
    }
}

contract GeniusVaultFuzzTest is Test {
    GeniusVault public vault;
    MockStablecoin public USDC;
    GeniusProxyCall public proxyCall;
    GeniusVaultHandler public handler;

    address public owner;
    address public trader;
    address public orchestrator;

    function setUp() public {
        // Deploy contracts directly without forking
        USDC = new MockStablecoin();
        owner = makeAddr("OWNER");
        trader = makeAddr("TRADER");
        orchestrator = makeAddr("ORCHESTRATOR");

        // Deploy ProxyCall
        proxyCall = new GeniusProxyCall(owner, new address[](0));

        // Deploy Vault with proxy
        vm.startPrank(owner);
        GeniusVault implementation = new GeniusVault();

        bytes memory data = abi.encodeWithSelector(
            GeniusVault.initialize.selector,
            address(USDC),
            owner,
            address(proxyCall),
            7_500
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);
        vault = GeniusVault(address(proxy));

        // Setup permissions
        proxyCall.grantRole(proxyCall.CALLER_ROLE(), address(vault));
        vault.grantRole(vault.ORCHESTRATOR_ROLE(), orchestrator);
        vault.grantRole(vault.ORCHESTRATOR_ROLE(), address(this));
        vault.setTargetChainMinFee(address(USDC), 42, 1 ether);

        vm.stopPrank();

        // Setup handler
        handler = new GeniusVaultHandler(
            vault,
            USDC,
            proxyCall,
            owner,
            orchestrator
        );

        targetContract(address(handler));
        targetSender(address(this));

        // Configure the number of runs and depth
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = GeniusVaultHandler.stake.selector;
        selectors[1] = GeniusVaultHandler.withdraw.selector;
        selectors[2] = GeniusVaultHandler.createOrder.selector;
        selectors[3] = GeniusVaultHandler.fillOrder.selector;
        selectors[4] = GeniusVaultHandler.claimFees.selector;

        targetSelector(
            FuzzSelector({addr: address(handler), selectors: selectors})
        );
    }

    // Reset operation count before each test run
    function pre_invariant() public {
        handler.resetOperationCount();
    }

    // Invariant 1: Total assets should always be >= staked assets
    function invariant_totalAssetsExceedStaked() public {
        assertGe(
            vault.stablecoinBalance(),
            vault.totalStakedAssets(),
            "Total assets less than staked assets"
        );
    }

    // Invariant 2: Collected fees should be >= claimed fees
    function invariant_feesConsistency() public {
        assertGe(
            vault.feesCollected(),
            vault.feesClaimed(),
            "Claimed fees exceed collected fees"
        );
    }

    // Invariant 3: Handler's fee tracking should match vault
    function invariant_feeTracking() public {
        assertEq(
            handler.totalFeesCollected() - handler.totalFeesClaimed(),
            vault.claimableFees(),
            "Fee tracking mismatch"
        );
    }

    // Invariant 4: Min liquidity calculation should be consistent
    function invariant_minLiquidityConsistency() public {
        uint256 expectedMin = vault.totalStakedAssets() > 0
            ? vault.totalStakedAssets() -
                ((vault.totalStakedAssets() * vault.rebalanceThreshold()) /
                    10_000)
            : 0;
        expectedMin += vault.claimableFees();

        assertEq(
            vault.minLiquidity(),
            expectedMin,
            "Min liquidity calculation mismatch"
        );
    }

    // Invariant 5: Order status transitions should be valid
    function invariant_orderStatusTransitions() public {
        bytes32[] memory allOrders = getAllOrders();
        for (uint256 i = 0; i < allOrders.length; i++) {
            bytes32 orderHash = allOrders[i];
            IGeniusVault.OrderStatus status = vault.orderStatus(orderHash);
            IGeniusVault.OrderStatus expectedStatus = handler
                .expectedOrderStatus(orderHash);

            assertEq(
                uint256(status),
                uint256(expectedStatus),
                "Invalid order status transition"
            );
        }
    }

    // Invariant 6: Available assets calculation should be consistent
    function invariant_availableAssetsConsistency() public {
        uint256 totalAssets = vault.stablecoinBalance();
        uint256 minLiquidity = vault.minLiquidity();

        uint256 expected = totalAssets > minLiquidity
            ? totalAssets - minLiquidity
            : 0;

        assertEq(
            vault.availableAssets(),
            expected,
            "Available assets calculation mismatch"
        );
    }

    // Helper function to get all orders (simplified for example)
    function getAllOrders() internal view returns (bytes32[] memory) {
        // In practice, you would track this in the handler
        // This is just a placeholder
        return new bytes32[](0);
    }

    function invariant_callSummary() public view {
        console.log("Total orders created:", handler.totalOrdersCreated());
        console.log("Total orders filled:", handler.totalOrdersFilled());
        console.log("Total fees collected:", handler.totalFeesCollected());
        console.log("Total fees claimed:", handler.totalFeesClaimed());
        console.log("Total staked:", handler.totalStaked());
    }
}
