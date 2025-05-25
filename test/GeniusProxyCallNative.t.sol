// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import {Test, console} from "forge-std/Test.sol";
import {GeniusProxyCall} from "src/GeniusProxyCall.sol";
import {GeniusRouter} from "src/GeniusRouter.sol";
import {GeniusVault} from "src/GeniusVault.sol";
import {GeniusErrors} from "src/libs/GeniusErrors.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MockDEXRouter} from "./mocks/MockDEXRouter.sol";
import {MockDepositContract} from "./mocks/MockDeposit.sol";
import {MockDepositRouter} from "./mocks/MockDepositRouter.sol";

contract GeniusProxyCallNativeTokenTest is Test {
    uint256 constant BASE_ROUTER_WETH_BALANCE = 100 ether;
    uint256 constant BASE_PROXY_USDC_BALANCE = 100 ether;
    uint256 constant BASE_DEX_ETH_BALANCE = 50 ether;
    uint256 constant destChainId = 1;

    bytes32 public DOMAIN_SEPERATOR;

    uint256 avalanche;
    string private rpc = vm.envString("AVALANCHE_RPC_URL");

    GeniusProxyCall public PROXYCALL;
    GeniusRouter public GENIUS_ROUTER;
    GeniusVault public GENIUS_VAULT;

    MockDepositContract public MOCK_DEPOSIT;
    MockDepositRouter public MOCK_DEPOSIT_ROUTER;

    ERC20 public USDC;
    ERC20 public WETH;

    MockDEXRouter DEX_ROUTER;
    address ADMIN = makeAddr("ADMIN");
    address CALLER = makeAddr("CALLER");

    address USER;
    uint256 USER_PK;

    address constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    function setUp() public {
        avalanche = vm.createFork(rpc);

        vm.selectFork(avalanche);
        assertEq(vm.activeFork(), avalanche);

        (USER, USER_PK) = makeAddrAndKey("user");

        DEX_ROUTER = new MockDEXRouter();

        PROXYCALL = new GeniusProxyCall(ADMIN, new address[](0));
        USDC = ERC20(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E);
        WETH = ERC20(0x49D5c2BdFfac6CE2BFdB6640F4F80f226bc10bAB);

        MOCK_DEPOSIT = new MockDepositContract();
        MOCK_DEPOSIT_ROUTER = new MockDepositRouter(address(MOCK_DEPOSIT));

        vm.startPrank(ADMIN, ADMIN);

        PROXYCALL.grantRole(PROXYCALL.CALLER_ROLE(), address(CALLER));

        deal(address(WETH), address(DEX_ROUTER), BASE_ROUTER_WETH_BALANCE);
        deal(address(USDC), address(PROXYCALL), BASE_PROXY_USDC_BALANCE);

        // Add ETH balance to DEX router for native swaps
        vm.deal(address(DEX_ROUTER), BASE_DEX_ETH_BALANCE);
    }

    // Test 1: Execute with native value - testing direct ETH transfer
    function testExecuteWithNativeValue() public {
        uint256 depositBalanceBefore = address(MOCK_DEPOSIT).balance;

        vm.deal(CALLER, 5 ether);
        vm.startPrank(CALLER);

        // Call depositETH directly on the deposit contract
        bytes memory data = abi.encodeWithSelector(
            MOCK_DEPOSIT.depositETH.selector
        );

        PROXYCALL.execute{value: 5 ether}(address(MOCK_DEPOSIT), data);
        vm.stopPrank();

        assertEq(
            address(MOCK_DEPOSIT).balance - depositBalanceBefore,
            5 ether,
            "Deposit should receive 5 ETH"
        );
    }

    // Test 2: Test approveTokenExecuteAndVerify with native token as OUTPUT (token to ETH swap)
    function testApproveTokenExecuteAndVerifyWithNativeTokenOutput() public {
        // This tests swapping FROM USDC TO ETH
        bytes memory swapData = abi.encodeWithSelector(
            DEX_ROUTER.swapTokenToETH.selector,
            address(USDC),
            BASE_PROXY_USDC_BALANCE,
            USER
        );

        uint256 userETHBefore = USER.balance;

        vm.startPrank(CALLER);

        uint256 amountOut = PROXYCALL.approveTokenExecuteAndVerify(
            address(USDC), // Input token that needs approval
            address(DEX_ROUTER),
            swapData,
            NATIVE_TOKEN, // Output token is ETH
            BASE_DEX_ETH_BALANCE / 2,
            USER
        );
        vm.stopPrank();

        assertEq(
            amountOut,
            BASE_DEX_ETH_BALANCE / 2,
            "Amount out should match expected"
        );
        assertEq(
            USER.balance - userETHBefore,
            BASE_DEX_ETH_BALANCE / 2,
            "User should receive ETH"
        );
    }

    // Test 2b: Test direct ETH swap using execute
    function testExecuteETHSwap() public {
        // For ETH input swaps, use execute directly
        deal(address(USDC), address(DEX_ROUTER), BASE_PROXY_USDC_BALANCE);

        bytes memory swapData = abi.encodeWithSelector(
            DEX_ROUTER.swapETHToToken.selector,
            address(USDC),
            USER
        );

        uint256 userUSDCBefore = USDC.balanceOf(USER);

        vm.deal(CALLER, 10 ether);
        vm.startPrank(CALLER);

        // Use execute with ETH value for ETH input swaps
        PROXYCALL.execute{value: 10 ether}(address(DEX_ROUTER), swapData);
        vm.stopPrank();

        assertEq(
            USDC.balanceOf(USER) - userUSDCBefore,
            BASE_PROXY_USDC_BALANCE / 2,
            "User should receive USDC"
        );
    }

    // Test 3: Test simple token approval and execution
    function testApproveTokenExecute() public {
        bytes memory swapData = abi.encodeWithSelector(
            DEX_ROUTER.bridge.selector,
            address(USDC),
            BASE_PROXY_USDC_BALANCE
        );

        vm.startPrank(CALLER);
        PROXYCALL.approveTokenExecute(
            address(USDC),
            address(DEX_ROUTER),
            swapData
        );
        vm.stopPrank();

        assertEq(USDC.balanceOf(address(DEX_ROUTER)), BASE_PROXY_USDC_BALANCE);
    }

    // Test 4: Test transferTokenAndExecute with native value
    function testTransferTokenAndExecuteWithNativeValue() public {
        bytes memory depositData = abi.encodeWithSelector(
            MOCK_DEPOSIT_ROUTER.depositBalance.selector,
            address(USDC)
        );

        uint256 depositUSDCBefore = USDC.balanceOf(address(MOCK_DEPOSIT));

        vm.deal(CALLER, 3 ether);
        vm.startPrank(CALLER);
        PROXYCALL.transferTokenAndExecute{value: 3 ether}(
            address(USDC),
            address(MOCK_DEPOSIT_ROUTER),
            depositData
        );
        vm.stopPrank();

        assertEq(
            USDC.balanceOf(address(MOCK_DEPOSIT)) - depositUSDCBefore,
            BASE_PROXY_USDC_BALANCE,
            "Deposit should receive USDC"
        );
        // Note: ETH is sent to the router, not necessarily to the deposit contract
        assertEq(
            address(MOCK_DEPOSIT_ROUTER).balance,
            3 ether,
            "Router should receive ETH"
        );
    }

    // Test 5: Test call function with no swap and no call
    function testCallNoSwapNoCall() public {
        vm.startPrank(CALLER);
        (address effTOut, uint256 effAOut, bool success) = PROXYCALL.call(
            USER,
            address(0),
            address(0),
            address(USDC),
            address(USDC),
            BASE_PROXY_USDC_BALANCE,
            "",
            ""
        );
        vm.stopPrank();

        assertEq(effTOut, address(USDC));
        assertEq(effAOut, BASE_PROXY_USDC_BALANCE);
        assertEq(success, true);
        assertEq(USDC.balanceOf(USER), BASE_PROXY_USDC_BALANCE);
    }

    // Test 6: Test call function with regular token swap (not native)
    function testCallSwapTokenToToken() public {
        bytes memory data = abi.encodeWithSelector(
            DEX_ROUTER.swapTo.selector,
            address(USDC),
            address(WETH),
            BASE_PROXY_USDC_BALANCE,
            USER
        );

        vm.startPrank(CALLER);
        (address effTOut, uint256 effAOut, bool success) = PROXYCALL.call(
            USER,
            address(DEX_ROUTER),
            address(0),
            address(USDC),
            address(WETH),
            BASE_ROUTER_WETH_BALANCE / 2,
            data,
            ""
        );
        vm.stopPrank();

        assertEq(effTOut, address(WETH), "Effective tokenOut should be WETH");
        assertEq(
            effAOut,
            BASE_ROUTER_WETH_BALANCE / 2,
            "Effective amountOut should be half of the router's WETH balance"
        );
        assertEq(success, true, "Operation should be successful");
        assertEq(WETH.balanceOf(USER), BASE_ROUTER_WETH_BALANCE / 2);
    }

    // Test 7: Test failed swap recovery
    function testCallFailedSwap() public {
        bytes memory data = abi.encodeWithSelector(
            DEX_ROUTER.swapTo.selector,
            address(USDC),
            address(WETH),
            BASE_PROXY_USDC_BALANCE + 1 ether, // Try to swap more than available
            USER
        );

        vm.startPrank(CALLER);
        (address effTOut, uint256 effAOut, bool success) = PROXYCALL.call(
            USER,
            address(DEX_ROUTER),
            address(0),
            address(USDC),
            address(WETH),
            BASE_ROUTER_WETH_BALANCE / 2,
            data,
            ""
        );
        vm.stopPrank();

        assertEq(effTOut, address(USDC), "Should fall back to USDC");
        assertEq(
            effAOut,
            BASE_PROXY_USDC_BALANCE,
            "Should return original USDC amount"
        );
        assertEq(success, false, "Operation should fail");
        assertEq(
            USDC.balanceOf(USER),
            BASE_PROXY_USDC_BALANCE,
            "User should receive USDC back"
        );
    }

    // Test 8: Test multiSend functionality
    function testMultiSend() public {
        address[] memory targets = new address[](2);
        bytes[] memory data = new bytes[](2);
        uint256[] memory values = new uint256[](2);

        // First call: transfer some USDC
        targets[0] = address(USDC);
        data[0] = abi.encodeWithSelector(
            USDC.transfer.selector,
            USER,
            50 ether
        );
        values[0] = 0;

        // Second call: transfer remaining USDC
        targets[1] = address(USDC);
        data[1] = abi.encodeWithSelector(
            USDC.transfer.selector,
            address(DEX_ROUTER),
            50 ether
        );
        values[1] = 0;

        bytes memory transactions = _encodeTransactions(targets, values, data);

        vm.startPrank(CALLER);
        bytes memory multiSendData = abi.encodeWithSelector(
            GeniusProxyCall.multiSend.selector,
            transactions
        );
        PROXYCALL.execute(address(PROXYCALL), multiSendData);
        vm.stopPrank();

        assertEq(USDC.balanceOf(USER), 50 ether);
        assertEq(USDC.balanceOf(address(DEX_ROUTER)), 50 ether);
    }

    // Test 9: Test access control
    function testRevertWhenUnauthorizedCaller() public {
        vm.startPrank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(GeniusErrors.InvalidCaller.selector)
        );
        PROXYCALL.execute(address(USDC), "");
        vm.stopPrank();
    }

    // Test 10: Test native balance recovery in call function
    function testCallWithETHBalanceRecovery() public {
        // Give ProxyCall some ETH
        vm.deal(address(PROXYCALL), 5 ether);

        // Do a simple USDC transfer (no swap, no call)
        vm.startPrank(CALLER);
        (, , bool success) = PROXYCALL.call(
            USER,
            address(0),
            address(0),
            address(USDC),
            address(USDC),
            BASE_PROXY_USDC_BALANCE,
            "",
            ""
        );
        vm.stopPrank();

        assertEq(success, true);
        assertEq(USDC.balanceOf(USER), BASE_PROXY_USDC_BALANCE);

        // Check that ETH was also sent to the user
        assertEq(USER.balance, 5 ether, "User should receive the ETH balance");
    }

    // Helper function to encode transactions
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

        return encoded;
    }
}

// Helper contract that rejects ETH
contract RevertingReceiver {
    receive() external payable {
        revert("ETH not accepted");
    }
}
