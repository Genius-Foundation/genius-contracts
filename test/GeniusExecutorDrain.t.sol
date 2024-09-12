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
import {MaliciousContract} from "./mocks/MaliciousContract.sol";
import {MockDEXRouter} from "./mocks/MockDEXRouter.sol";

contract GeniusExecutorDrain is Test {
    uint256 avalanche;
    string private rpc = vm.envString("AVALANCHE_RPC_URL");
    bytes32 public DOMAIN_SEPERATOR;

    address public OWNER;
    address public trader;
    bytes32 public receiver;
    uint256 private privateKey;
    uint48 private nonce;
    address public coinReceiver;

    address public permit2Address = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    TestERC20 public USDC;
    TestERC20 public WETH;

    PermitSignature public sigUtils;
    IEIP712 public permit2;

    GeniusVault public VAULT;
    GeniusExecutor public EXECUTOR;
    MaliciousContract public MALICIOUS;
    MockDEXRouter public DEX_ROUTER;

    function setupMaliciousTest() internal {
        vm.startPrank(OWNER);
        EXECUTOR.setAllowedTarget(address(MALICIOUS), true);
        vm.stopPrank();

        deal(address(USDC), address(EXECUTOR), 100 ether);
        deal(address(WETH), address(EXECUTOR), 100 ether);
        vm.deal(address(EXECUTOR), 1 ether);
        vm.deal(trader, 2 ether);
    }

    function setupMultiSwapParams() internal view returns (address[] memory, bytes[] memory, uint256[] memory) {
        address[] memory targets = new address[](4);
        targets[0] = address(USDC);
        targets[1] = address(WETH);
        targets[2] = address(DEX_ROUTER);
        targets[3] = address(DEX_ROUTER);

        bytes[] memory data = new bytes[](4);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", address(DEX_ROUTER), 10 ether);
        data[1] = abi.encodeWithSignature("approve(address,uint256)", address(DEX_ROUTER), 5 ether);
        data[2] = abi.encodeWithSignature("swap(address,address,uint256)", address(USDC), address(WETH), 10 ether);
        data[3] = abi.encodeWithSignature("swap(address,address,uint256)", address(WETH), address(USDC), 5 ether);

        uint256[] memory values = new uint256[](4);
        values[0] = 0;
        values[1] = 0;
        values[2] = 0;
        values[3] = 0;

        return (targets, data, values);
    }

    function generatePermitBatchAndSignature(
        address owner,
        address spender,
        address[2] memory tokens,
        uint160[2] memory amounts
    ) internal returns (IAllowanceTransfer.PermitBatch memory, bytes memory) {
        require(tokens.length == amounts.length, "Tokens and amounts length mismatch");

        IAllowanceTransfer.PermitDetails[] memory permitDetails = new IAllowanceTransfer.PermitDetails[](tokens.length);
        
        for (uint i = 0; i < tokens.length; i++) {
            permitDetails[i] = IAllowanceTransfer.PermitDetails({
                token: tokens[i],
                amount: amounts[i],
                expiration: 1900000000,
                nonce: nonce
            });
        }

        nonce++;

        IAllowanceTransfer.PermitBatch memory permitBatch = IAllowanceTransfer.PermitBatch({
            details: permitDetails,
            spender: spender,
            sigDeadline: 1900000000
        });

        // Get the private key for the owner (assuming we have a mapping or way to get this in tests)
        uint256 ownerPrivateKey = getPrivateKey(owner);

        bytes memory signature = sigUtils.getPermitBatchSignature(
            permitBatch,
            ownerPrivateKey,
            DOMAIN_SEPERATOR
        );

        return (permitBatch, signature);
    }

    // Helper function to get the private key for an address (implement this based on your test setup)
    function getPrivateKey(address addr) internal view returns (uint256) {
        if (addr == trader) {
            return privateKey; // Assuming 'privateKey' is already defined for the trader
        }
        // Add more conditions for other addresses if needed
        revert("Private key not found for address");
    }

    function setUp() public {
        avalanche = vm.createFork(rpc);
        vm.selectFork(avalanche);
        assertEq(vm.activeFork(), avalanche);

        OWNER = makeAddr("owner");
        (address traderAddress, uint256 traderKey) = makeAddrAndKey("trader");
        trader = traderAddress;
        receiver = keccak256(abi.encodePacked(trader));
        privateKey = traderKey;
        coinReceiver = makeAddr("coinReceiver");

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
        
        EXECUTOR = new GeniusExecutor(permit2Address, address(VAULT), OWNER, new address[](0));
        VAULT.setExecutor(address(EXECUTOR));
        MALICIOUS = new MaliciousContract(address(EXECUTOR));
        DEX_ROUTER = new MockDEXRouter();
        vm.stopPrank();


        deal(address(USDC), trader, 100 ether);
        deal(address(WETH), trader, 100 ether);

        vm.startPrank(trader);
        USDC.approve(permit2Address, type(uint256).max);
        WETH.approve(permit2Address, type(uint256).max);
        vm.stopPrank();
    }

    /**
     * @dev This function tests the native transfer functionality.
     * It performs the following steps:
     * 1. Saves the initial balance of the EXECUTOR contract.
     * 2. Deals 2 ether to the trader.
     * 3. Attempts to transfer 1 ether to the EXECUTOR contract.
     * 4. Expects a revert as the EXECUTOR contract does not accept native tokens.
     * 5. Asserts that the balances of the EXECUTOR contract and the trader remain the same.
     */
    function testNativeTransfer() public {
        uint256 initialBalance = address(EXECUTOR).balance;

        vm.startPrank(trader);
        vm.deal(trader, 2 ether);

        vm.expectRevert("Native tokens not accepted directly");
        (bool success, ) = payable(address(EXECUTOR)).call{value: 1 ether}("");
        assertEq(success, true, "callback will not return false");
        vm.stopPrank();

        assertEq(address(EXECUTOR).balance, initialBalance, "EXECUTOR's balance should not change");
        assertEq(trader.balance, 2 ether, "Trader's balance should not change");
    }

    /**
     * @dev This function tests the `aggregate` function in the `EXECUTOR` contract.
     * It performs two swaps: one through an approved DEX_ROUTER contract and another through an unauthorized MALICIOUS contract.
     * The function verifies the balances of the EXECUTOR contract, the MALICIOUS contract, and the trader before and after the swaps.
     * It also checks for expected reverts in case of invalid targets.
     */
    function testAggregateMaliciousCall() public {
        uint256 initialTraderBalance = trader.balance;

        vm.startPrank(OWNER);
        EXECUTOR.setAllowedTarget(address(DEX_ROUTER), true);
        vm.stopPrank();

        // Fund EXECUTOR
        deal(address(USDC), address(EXECUTOR), 100 ether);
        deal(address(WETH), address(EXECUTOR), 100 ether);
        vm.deal(address(EXECUTOR), 1 ether);

        uint256 initialBalance = address(EXECUTOR).balance;
        uint256 initialUSDCBalance = USDC.balanceOf(address(EXECUTOR));
        uint256 initialWETHBalance = WETH.balanceOf(address(EXECUTOR));

        // Approve the DEX_ROUTER to spend USDC
        USDC.approve(address(DEX_ROUTER), type(uint256).max);

        // Test swap through approved DEX_ROUTER
        address[] memory initial_targets = new address[](2);
        initial_targets[0] = address(USDC);
        initial_targets[1] = address(DEX_ROUTER);

        bytes[] memory initial_data = new bytes[](2);
        initial_data[0] = abi.encodeWithSignature(
            "approve(address,uint256)",
            address(DEX_ROUTER),
            1 ether
        );
        initial_data[1] = abi.encodeWithSignature(
            "swap(address,address,uint256)",
            address(USDC),
            address(WETH),
            1 ether
        );

        uint256[] memory initial_values = new uint256[](2);
        initial_values[0] = 0;
        initial_values[1] = 0;

        vm.prank(trader);
        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.InvalidTarget.selector, address(USDC)));
        EXECUTOR.aggregate(initial_targets, initial_data, initial_values);

        // Check balances after successful swap
        assertEq(USDC.balanceOf(address(EXECUTOR)), initialUSDCBalance, "USDC balance should not change");
        assertEq(WETH.balanceOf(address(EXECUTOR)), initialWETHBalance, "WETH balance should not change");

        // Reset balances for malicious test
        deal(address(USDC), address(EXECUTOR), initialUSDCBalance);
        deal(address(WETH), address(EXECUTOR), initialWETHBalance);

        // Test swap through unauthorized MALICIOUS contract
        address[] memory targets = new address[](1);
        bytes[] memory data = new bytes[](1);
        uint256[] memory values = new uint256[](1);

        targets[0] = address(MALICIOUS);
        data[0] = abi.encodeWithSignature(
            "maliciousCall(address,address)",
            address(USDC),
            address(WETH)
        );
        values[0] = 1 ether;

        vm.prank(trader);
        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.InvalidTarget.selector, address(MALICIOUS)));
        EXECUTOR.aggregate(targets, data, values);

        // Check balances after failed malicious swap
        assertEq(address(EXECUTOR).balance, initialBalance, "Native token balance should not change");
        assertEq(USDC.balanceOf(address(EXECUTOR)), initialUSDCBalance, "USDC balance should not change");
        assertEq(WETH.balanceOf(address(EXECUTOR)), initialWETHBalance, "WETH balance should not change");
        
        assertEq(address(MALICIOUS).balance, 0, "Malicious contract should not receive any ether");
        assertEq(USDC.balanceOf(address(MALICIOUS)), 0, "Malicious contract should not receive any USDC");
        assertEq(WETH.balanceOf(address(MALICIOUS)), 0, "Malicious contract should not receive any WETH");
        
        assertEq(trader.balance, initialTraderBalance, "Trader's ether balance should not change");
        assertEq(USDC.balanceOf(trader), 100 ether, "Trader's USDC balance should not change");
        assertEq(WETH.balanceOf(trader), 100 ether, "Trader's WETH balance should not change");
    }

    function testAggregateWithPermit2MaliciousCallRevert() public {
        setupMaliciousTest();

        address[] memory targets = new address[](1);
        targets[0] = address(MALICIOUS);

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("maliciousCall(address,address)", address(USDC), address(WETH));

        uint256[] memory values = new uint256[](1);
        values[0] = 1 ether;

        (IAllowanceTransfer.PermitBatch memory permitBatch, bytes memory signature) = 
            generatePermitBatchAndSignature(trader, address(EXECUTOR), [address(USDC), address(WETH)], [uint160(10 ether), uint160(5 ether)]);

        vm.prank(trader);
        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.ExternalCallFailed.selector, address(MALICIOUS), 0));
        EXECUTOR.aggregateWithPermit2{value: 1 ether}(
            targets,
            data,
            values,
            permitBatch,
            signature,
            trader
        );
    }

    function testExecutorBalancesUnchanged() public {
        setupMaliciousTest();

        address[] memory targets = new address[](1);
        targets[0] = address(MALICIOUS);

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("maliciousCall(address,address)", address(USDC), address(WETH));

        uint256[] memory values = new uint256[](1);
        values[0] = 1 ether;

        (IAllowanceTransfer.PermitBatch memory permitBatch, bytes memory signature) = 
            generatePermitBatchAndSignature(trader, address(EXECUTOR), [address(USDC), address(WETH)], [uint160(10 ether), uint160(5 ether)]);

        vm.prank(trader);
        try EXECUTOR.aggregateWithPermit2{value: 1 ether}(
            targets,
            data,
            values,
            permitBatch,
            signature,
            trader
        ) {
            assert(false); // This should not be reached
        } catch {
            // This is expected, now we check the balances
        }

        assertEq(address(EXECUTOR).balance, 1 ether, "Native token balance should not change");
        assertEq(USDC.balanceOf(address(EXECUTOR)), 100 ether, "USDC balance should not change");
        assertEq(WETH.balanceOf(address(EXECUTOR)), 100 ether, "WETH balance should not change");
    }

    function testMaliciousContractBalancesUnchanged() public {
        setupMaliciousTest();

        address[] memory targets = new address[](1);
        targets[0] = address(MALICIOUS);

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("maliciousCall(address,address)", address(USDC), address(WETH));

        uint256[] memory values = new uint256[](1);
        values[0] = 1 ether;

        (IAllowanceTransfer.PermitBatch memory permitBatch, bytes memory signature) = 
            generatePermitBatchAndSignature(trader, address(EXECUTOR), [address(USDC), address(WETH)], [uint160(10 ether), uint160(5 ether)]);

        vm.prank(trader);
        try EXECUTOR.aggregateWithPermit2{value: 1 ether}(
            targets,
            data,
            values,
            permitBatch,
            signature,
            trader
        ) {
            assert(false); // This should not be reached
        } catch {
            // This is expected, now we check the balances
        }

        assertEq(address(MALICIOUS).balance, 0, "Malicious contract should not receive any ether");
        assertEq(USDC.balanceOf(address(MALICIOUS)), 0, "Malicious contract should not receive any USDC");
        assertEq(WETH.balanceOf(address(MALICIOUS)), 0, "Malicious contract should not receive any WETH");
    }

    function testTraderBalancesUnchanged() public {
        setupMaliciousTest();

        address[] memory targets = new address[](1);
        targets[0] = address(MALICIOUS);

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("maliciousCall(address,address)", address(USDC), address(WETH));

        uint256[] memory values = new uint256[](1);
        values[0] = 2 ether;

        (IAllowanceTransfer.PermitBatch memory permitBatch, bytes memory signature) = 
            generatePermitBatchAndSignature(trader, address(EXECUTOR), [address(USDC), address(WETH)], [uint160(10 ether), uint160(5 ether)]);

        vm.prank(trader);
        try EXECUTOR.aggregateWithPermit2{value: 1 ether}(
            targets,
            data,
            values,
            permitBatch,
            signature,
            trader
        ) {
            assert(false); // This should not be reached
        } catch {
            // This is expected, now we check the balances
        }

        assertEq(trader.balance, 2 ether, "Trader's ether balance should not change");
        assertEq(USDC.balanceOf(trader), 100 ether, "Trader's USDC balance should not change");
        assertEq(WETH.balanceOf(trader), 100 ether, "Trader's WETH balance should not change");
    }


    /**
     * @dev This function tests the successful execution of multiSwapAndDeposit.
     * It sets up the necessary parameters for the multiSwap, generates permit batch and signature,
     * records the initial balances, executes the multiSwapAndDeposit, and asserts the final balances.
     * 
     * The function performs the following steps:
     * 1. Starts the prank by calling `startPrank` function with the `OWNER` address.
     * 2. Initializes the executor by calling `initialize` function with an array of router addresses.
     * 3. Stops the prank by calling `stopPrank` function.
     * 4. Sets up the targets, data, and values for the multiSwap by calling `setupMultiSwapParams` function.
     * 5. Generates permit batch and signature by calling `generatePermitBatchAndSignature` function with the trader address,
     *    executor address, and an array of token addresses and values.
     * 6. Records the initial balances of the trader and the vault.
     * 7. Executes the multiSwapAndDeposit by calling `multiSwapAndDeposit` function with the targets, data, values,
     *    permit batch, signature, and trader address.
     * 8. Asserts the final balances of the trader and the vault.
     * 
     */
    function testSuccessfulMultiSwapAndDeposit() public {
        vm.startPrank(OWNER);
        EXECUTOR.setAllowedTarget(address(DEX_ROUTER), true);
        vm.stopPrank();


        // Setup targets, data, and values for the multiSwap
        (address[] memory targets, bytes[] memory data, uint256[] memory values) = setupMultiSwapParams();

        // Generate permit batch and signature
        (IAllowanceTransfer.PermitBatch memory permitBatch, bytes memory signature) = 
            generatePermitBatchAndSignature(trader, address(EXECUTOR), [address(USDC), address(WETH)], [uint160(10 ether), uint160(5 ether)]);

        uint256 initialVaultUSDCBalance = USDC.balanceOf(address(VAULT));

        // Execute multiSwapAndDeposit
        vm.prank(trader);
        EXECUTOR.multiSwapAndDeposit(
            keccak256("order"),
            targets,
            data,
            values,
            permitBatch,
            signature,
            trader,
            42,
            uint32(block.timestamp + 1000),
            1 ether,
            receiver
        );

        // Assert final balances
        assertEq(USDC.balanceOf(trader), 100 ether - 10 ether, "Trader USDC balance should decrease by 10 ether");
        assertEq(WETH.balanceOf(trader), 100 ether - 5 ether, "Trader WETH balance should decrease by 5 ether");
        assertEq(USDC.balanceOf(address(VAULT)), initialVaultUSDCBalance + 10 ether, "Vault should receive the deposited USDC");
    }

    /**
     * @dev This function tests the scenario where the length of the array passed to `multiSwapAndDeposit` does not match the expected length.
     * It performs the following steps:
     * 1. Starts a prank by calling `startPrank` function with the `OWNER` address.
     * 2. Initializes the `EXECUTOR` contract with an array of routers.
     * 3. Stops the prank by calling `stopPrank` function.
     * 4. Sets up the parameters for multiple swaps by calling `setupMultiSwapParams` function.
     * 5. Generates a permit batch and signature by calling `generatePermitBatchAndSignature` function.
     * 6. Initiates a prank on the `trader` address.
     * 7. Expects the transaction to revert with the `ArrayLengthsMismatch` error.
     * 8. Calls the `multiSwapAndDeposit` function with mismatched array length, permit batch, signature, and trader address.
     */
    function testMultiSwapAndDepositArrayLengthMismatch() public {
        uint16 destChainId = 42;
        uint32 fillDeadline = uint32(block.timestamp + 1000);

        vm.startPrank(OWNER);
        EXECUTOR.setAllowedTarget(address(DEX_ROUTER), true);
        vm.stopPrank();

        (address[] memory targets, bytes[] memory data,) = setupMultiSwapParams();
        (IAllowanceTransfer.PermitBatch memory permitBatch, bytes memory signature) = 
            generatePermitBatchAndSignature(trader, address(EXECUTOR), [address(USDC), address(WETH)], [uint160(10 ether), uint160(5 ether)]);

        vm.prank(trader);
        vm.expectRevert(GeniusErrors.ArrayLengthsMismatch.selector);
        EXECUTOR.multiSwapAndDeposit(
            keccak256("order"),
            targets,
            data,
            new uint256[](1), // Mismatched length
            permitBatch,
            signature,
            trader,
            destChainId,
            fillDeadline,
            1 ether,
            receiver
        );
    }

    /**
     * @dev This function is used to test the `multiSwapAndDeposit` function when an invalid router address is provided.
     * It performs the following steps:
     * 1. Starts a prank by calling the `startPrank` function with the `OWNER` address.
     * 2. Initializes the `EXECUTOR` contract with an array of router addresses, where the first address is `DEX_ROUTER`.
     * 3. Stops the prank by calling the `stopPrank` function.
     * 4. Sets up the parameters for the `multiSwapAndDeposit` function by calling the `setupMultiSwapParams` function.
     * 5. Generates a permit batch and signature by calling the `generatePermitBatchAndSignature` function with the `trader` address,
     *    the `EXECUTOR` address, an array of token addresses (`USDC` and `WETH`), and an array of token values (10 ether and 5 ether).
     * 6. Creates a fake router address by calling the `makeAddr` function with the string "fakeRouter".
     * 7. Replaces the third and fourth elements of the `targets` array with the fake router address.
     * 8. Starts a prank by calling the `prank` function with the `trader` address.
     * 9. Expects a revert with the error message `InvalidTarget` and the fake router address.
     * 10. Calls the `multiSwapAndDeposit` function of the `EXECUTOR` contract with the following parameters:
     *     - `targets`: an array of contract addresses to call (including the fake router address)
     *     - `data`: an array of function call data
     *     - `values`: an array of ETH values to send with each function call
     *     - `permitBatch`: a permit batch struct containing permit data for token transfers
     *     - `signature`: a signature for the permit batch
     *     - `trader`: the address of the trader
     */
    function testMultiSwapAndDepositInvalidRouter() public {
        vm.startPrank(OWNER);
        EXECUTOR.setAllowedTarget(address(DEX_ROUTER), true);
        vm.stopPrank();

        (address[] memory targets, bytes[] memory data, uint256[] memory values) = setupMultiSwapParams();
        (IAllowanceTransfer.PermitBatch memory permitBatch, bytes memory signature) = 
            generatePermitBatchAndSignature(trader, address(EXECUTOR), [address(USDC), address(WETH)], [uint160(10 ether), uint160(5 ether)]);

        address fakeRouter = makeAddr("fakeRouter");
        targets[2] = fakeRouter;
        targets[3] = fakeRouter;

        vm.prank(trader);
        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.InvalidTarget.selector, fakeRouter));
        EXECUTOR.multiSwapAndDeposit(
            keccak256("order"),
            targets,
            data,
            values,
            permitBatch,
            signature,
            trader,
            42,
            uint32(block.timestamp + 1000),
            1 ether,
            receiver
        );
    }

    /**
     * @dev This function tests the execution of a multi-swap and deposit operation with a malicious contract.
     * It performs the following steps:
     * 1. Starts a prank by calling `startPrank` function with the `OWNER` address.
     * 2. Initializes the `EXECUTOR` contract with an array of router addresses.
     * 3. Stops the prank by calling `stopPrank` function.
     * 4. Generates a permit batch and signature using the `generatePermitBatchAndSignature` function.
     * 5. Creates an array of malicious contract targets and data.
     * 6. Sets the value for the malicious contract call.
     * 7. Calls the `deal` function to ensure the `trader` has enough ETH for the call.
     * 8. Calls the `prank` function with the `trader` address.
     * 9. Expects a revert with the `InvalidTarget` error if the `MALICIOUS` contract is called.
     * 10. Executes the `multiSwapAndDeposit` function of the `EXECUTOR` contract with the following parameters:
     *     - `maliciousTargets`: Array of malicious contract targets.
     *     - `maliciousData`: Array of malicious contract data.
     *     - `maliciousValues`: Array of values for the malicious contract calls.
     *     - `permitBatch`: Permit batch generated earlier.
     *     - `signature`: Signature generated earlier.
     *     - `trader`: Address of the trader.
     */
    function testMultiSwapAndDepositMaliciousContract() public {
        vm.startPrank(OWNER);
        EXECUTOR.setAllowedTarget(address(DEX_ROUTER), true);
        vm.stopPrank();

        (IAllowanceTransfer.PermitBatch memory permitBatch, bytes memory signature) = 
            generatePermitBatchAndSignature(trader, address(EXECUTOR), [address(USDC), address(WETH)], [uint160(10 ether), uint160(5 ether)]);

        address[] memory maliciousTargets = new address[](1);
        maliciousTargets[0] = address(MALICIOUS);

        bytes[] memory maliciousData = new bytes[](1);
        maliciousData[0] = abi.encodeWithSignature(
            "maliciousCall(address,address)",
            address(USDC),
            address(WETH)
        );

        uint256[] memory maliciousValues = new uint256[](1);
        maliciousValues[0] = 1 ether;

        vm.deal(trader, 1 ether);  // Ensure trader has enough ETH for the call

        vm.prank(trader);
        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.InvalidTarget.selector, address(MALICIOUS)));
        EXECUTOR.multiSwapAndDeposit{value: 1 ether}(
            keccak256("order"),
            maliciousTargets,
            maliciousData,
            maliciousValues,
            permitBatch,
            signature,
            trader,
            42,
            uint32(block.timestamp + 1000),
            1 ether,
            receiver
        );
    }

    function testNativeSwapAndDeposit() public {
        // Setup
        vm.startPrank(OWNER);
        EXECUTOR.setAllowedTarget(address(DEX_ROUTER), true);
        vm.stopPrank();

        // Fund trader with ETH
        vm.deal(trader, 10 ether);

        // Setup initial balances
        uint256 initialContractBalance = address(this).balance;
        uint256 initialVaultUSDCBalance = USDC.balanceOf(address(VAULT));

        // Prepare swap data
        bytes memory swapData = abi.encodeWithSignature(
            "swapToStables(address)",
            address(USDC)
        );

        // Execute nativeSwapAndDeposit
        vm.prank(trader);
        // Deal the DEX_ROUTER contract some USDC
        deal(address(USDC), address(DEX_ROUTER), 100 ether);
        EXECUTOR.nativeSwapAndDeposit{value: 100 ether}(
            keccak256("order"),
            address(DEX_ROUTER),
            swapData,
            100 ether,
            42,
            uint32(block.timestamp + 1000),
            1 ether,
            receiver
        );

        // Assert final balances
        assertEq(address(this).balance, initialContractBalance - 100 ether, "Trader ETH balance should decrease by 1 ether");
        assertEq(USDC.balanceOf(address(VAULT)), initialVaultUSDCBalance + MockDEXRouter(DEX_ROUTER).usdcAmountOut(), "Vault should receive the swapped USDC");

        // 1. Invalid target
        address invalidTarget = address(0x1234);
        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.InvalidTarget.selector, invalidTarget));
        vm.prank(trader);
        EXECUTOR.nativeSwapAndDeposit{value: 1 ether}(
            keccak256("order"),
            invalidTarget,
            swapData,
            1 ether,
            42,
            uint32(block.timestamp + 1000),
            1 ether,
            receiver
        );

        // 2. External call failed
        bytes memory invalidSwapData = abi.encodeWithSignature(
            "invalidFunction()",
            address(0),
            address(USDC),
            1 ether
        );
        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.ExternalCallFailed.selector, address(DEX_ROUTER), 0));
        vm.prank(trader);
        EXECUTOR.nativeSwapAndDeposit{value: 1 ether}(
            keccak256("order"),
            address(DEX_ROUTER),
            invalidSwapData,
            1 ether,
            42,
            uint32(block.timestamp + 1000),
            1 ether,
            receiver
        );

        // 3. Insufficient ETH sent
        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.InvalidNativeAmount.selector, 1 ether));
        vm.prank(trader);
        EXECUTOR.nativeSwapAndDeposit{value: 0.5 ether}(
            keccak256("order"),
            address(DEX_ROUTER),
            swapData,
            1 ether,
            42,
            uint32(block.timestamp + 1000),
            1 ether,
            receiver
        );
    }
}