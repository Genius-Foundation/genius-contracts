// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import {Test, console} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {GeniusProxyCall} from "src/GeniusProxyCall.sol";
import {GeniusRouter} from "src/GeniusRouter.sol";
import {GeniusVault} from "src/GeniusVault.sol";
import {GeniusErrors} from "src/libs/GeniusErrors.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MockDEXRouter} from "./mocks/MockDEXRouter.sol";
import {MockDepositContract} from "./mocks/MockDeposit.sol";
import {MockDepositRouter} from "./mocks/MockDepositRouter.sol";
import {MockERC20LikeUSDT} from "lib/solady/test/utils/mocks/MockERC20LikeUSDT.sol";

contract GeniusProxyCallTest is Test {
    uint256 constant BASE_ROUTER_WETH_BALANCE = 100 ether;
    uint256 constant BASE_PROXY_USDC_BALANCE = 100 ether;
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

    function setUp() public {
        avalanche = vm.createFork(rpc);

        vm.selectFork(avalanche);
        assertEq(vm.activeFork(), avalanche);

        (USER, USER_PK) = makeAddrAndKey("user");

        DEX_ROUTER = new MockDEXRouter();

        // Deploy implementation and proxy for upgradeable pattern
        GeniusProxyCall implementation = new GeniusProxyCall();
        bytes memory initData = abi.encodeWithSelector(
            GeniusProxyCall.initialize.selector,
            ADMIN,
            new address[](0)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );
        PROXYCALL = GeniusProxyCall(payable(address(proxy)));

        USDC = ERC20(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E);
        WETH = ERC20(0x49D5c2BdFfac6CE2BFdB6640F4F80f226bc10bAB);

        MOCK_DEPOSIT = new MockDepositContract();
        MOCK_DEPOSIT_ROUTER = new MockDepositRouter(address(MOCK_DEPOSIT));

        vm.startPrank(ADMIN, ADMIN);

        PROXYCALL.grantRole(PROXYCALL.CALLER_ROLE(), address(CALLER));

        deal(address(WETH), address(DEX_ROUTER), BASE_ROUTER_WETH_BALANCE);
        deal(address(USDC), address(PROXYCALL), BASE_PROXY_USDC_BALANCE);
    }

    function testExecute() public {
        bytes memory data = abi.encodeWithSelector(
            USDC.transfer.selector,
            address(DEX_ROUTER),
            BASE_PROXY_USDC_BALANCE
        );

        vm.startPrank(CALLER);
        PROXYCALL.execute(address(USDC), data);
        vm.stopPrank();

        assertEq(USDC.balanceOf(address(DEX_ROUTER)), BASE_PROXY_USDC_BALANCE);
    }

    function testExecuteRevertIfExernalCallFailed() public {
        bytes memory data = abi.encodeWithSelector(
            USDC.transfer.selector,
            address(DEX_ROUTER),
            BASE_PROXY_USDC_BALANCE + 1 ether
        );

        vm.startPrank(CALLER);

        vm.expectRevert(
            abi.encodeWithSelector(
                GeniusErrors.ExternalCallFailed.selector,
                address(USDC)
            )
        );

        PROXYCALL.execute(address(USDC), data);
        vm.stopPrank();
    }

    function testExecuteRevertIfTargetAddress0() public {
        bytes memory data = abi.encodeWithSelector(
            USDC.transfer.selector,
            address(DEX_ROUTER),
            BASE_PROXY_USDC_BALANCE
        );

        vm.startPrank(CALLER);

        vm.expectRevert(
            abi.encodeWithSelector(GeniusErrors.NonAddress0.selector)
        );
        PROXYCALL.execute(address(0), data);
        vm.stopPrank();
    }

    function testExecuteRevertIfTargetNotContract() public {
        bytes memory data = abi.encodeWithSelector(
            USDC.transfer.selector,
            address(DEX_ROUTER),
            BASE_PROXY_USDC_BALANCE
        );

        vm.startPrank(CALLER);

        vm.expectRevert(
            abi.encodeWithSelector(GeniusErrors.TargetIsNotContract.selector)
        );

        PROXYCALL.execute(USER, data);
        vm.stopPrank();
    }

    function testExecuteRevertIfUnauthorisedCaller() public {
        bytes memory data = abi.encodeWithSelector(
            USDC.transfer.selector,
            address(DEX_ROUTER),
            BASE_PROXY_USDC_BALANCE
        );

        vm.startPrank(USER);

        vm.expectRevert(
            abi.encodeWithSelector(GeniusErrors.InvalidCaller.selector)
        );

        PROXYCALL.execute(address(USDC), data);
        vm.stopPrank();
    }

    function testExecuteCanBeCalledBySelf() public {
        address[] memory targets = new address[](1);
        bytes[] memory data = new bytes[](1);
        uint256[] memory values = new uint256[](1);

        targets[0] = address(USDC);
        data[0] = abi.encodeWithSelector(
            USDC.transfer.selector,
            address(DEX_ROUTER),
            BASE_PROXY_USDC_BALANCE
        );
        values[0] = 0;

        bytes memory transactions = _encodeTransactions(targets, values, data);

        vm.startPrank(CALLER);
        PROXYCALL.execute(address(PROXYCALL), transactions);
        vm.stopPrank();
    }

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

    function testCallSwapNoCall() public {
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

    function testCallSwapAndCall() public {
        bytes memory swapData = abi.encodeWithSelector(
            DEX_ROUTER.swapTo.selector,
            address(USDC),
            address(WETH),
            BASE_PROXY_USDC_BALANCE,
            address(PROXYCALL)
        );

        bytes memory callData = abi.encodeWithSelector(
            MOCK_DEPOSIT_ROUTER.depositBalance.selector,
            address(WETH)
        );

        vm.startPrank(CALLER);
        (address effTOut, uint256 effAOut, bool success) = PROXYCALL.call(
            USER,
            address(DEX_ROUTER),
            address(MOCK_DEPOSIT_ROUTER),
            address(USDC),
            address(WETH),
            BASE_ROUTER_WETH_BALANCE / 2,
            swapData,
            callData
        );
        vm.stopPrank();

        assertEq(effTOut, address(WETH), "Effective tokenOut should be WETH");
        assertEq(
            effAOut,
            BASE_ROUTER_WETH_BALANCE / 2,
            "Effective amountOut should be half of the router's WETH balance"
        );
        assertEq(success, true, "Operation should be successful");
        assertEq(
            WETH.balanceOf(address(MOCK_DEPOSIT)),
            BASE_ROUTER_WETH_BALANCE / 2
        );
    }

    function testCallNoSwapAndCall() public {
        bytes memory callData = abi.encodeWithSelector(
            MOCK_DEPOSIT_ROUTER.depositBalance.selector,
            address(USDC)
        );

        vm.startPrank(CALLER);
        (address effTOut, uint256 effAOut, bool success) = PROXYCALL.call(
            USER,
            address(0),
            address(MOCK_DEPOSIT_ROUTER),
            address(USDC),
            address(USDC),
            BASE_PROXY_USDC_BALANCE,
            "",
            callData
        );
        vm.stopPrank();

        assertEq(effTOut, address(USDC), "Effective tokenOut should be USDC");
        assertEq(
            effAOut,
            BASE_PROXY_USDC_BALANCE,
            "Effective amountOut should be half of the router's USDC balance"
        );
        assertEq(success, true, "Operation should be successful");
        assertEq(
            USDC.balanceOf(address(MOCK_DEPOSIT)),
            BASE_PROXY_USDC_BALANCE
        );
    }

    function testCallFailedSwap() public {
        bytes memory data = abi.encodeWithSelector(
            DEX_ROUTER.swapTo.selector,
            address(USDC),
            address(WETH),
            BASE_PROXY_USDC_BALANCE + 1 ether,
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

        assertEq(effTOut, address(USDC), "Effective tokenOut should be USDC");
        assertEq(
            effAOut,
            BASE_PROXY_USDC_BALANCE,
            "Effective amountOut the USDC balance"
        );
        assertEq(success, false, "Operation should be not successful");
        assertEq(USDC.balanceOf(USER), BASE_PROXY_USDC_BALANCE);
    }

    function testCallSwapOutUnderMin() public {
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
            BASE_ROUTER_WETH_BALANCE / 2 + 1 ether,
            data,
            ""
        );
        vm.stopPrank();

        assertEq(effTOut, address(USDC), "Effective tokenOut should be USDC");
        assertEq(
            effAOut,
            BASE_PROXY_USDC_BALANCE,
            "Effective amountOut the USDC balance"
        );
        assertEq(success, false, "Operation should be not successful");
        assertEq(USDC.balanceOf(USER), BASE_PROXY_USDC_BALANCE);
    }

    function testCallFailedSwapAndCall() public {
        bytes memory swapData = abi.encodeWithSelector(
            DEX_ROUTER.swapTo.selector,
            address(USDC),
            address(WETH),
            BASE_PROXY_USDC_BALANCE + 1 ether,
            address(PROXYCALL)
        );

        bytes memory callData = abi.encodeWithSelector(
            MOCK_DEPOSIT_ROUTER.depositBalance.selector,
            address(WETH)
        );

        vm.startPrank(CALLER);
        (address effTOut, uint256 effAOut, bool success) = PROXYCALL.call(
            USER,
            address(DEX_ROUTER),
            address(MOCK_DEPOSIT_ROUTER),
            address(USDC),
            address(WETH),
            BASE_ROUTER_WETH_BALANCE / 2,
            swapData,
            callData
        );
        vm.stopPrank();

        assertEq(effTOut, address(USDC), "Effective tokenOut should be USDC");
        assertEq(
            effAOut,
            BASE_PROXY_USDC_BALANCE,
            "Effective amountOut the USDC balance"
        );
        assertEq(success, false, "Operation should be not successful");
        assertEq(USDC.balanceOf(USER), BASE_PROXY_USDC_BALANCE);
    }

    function testCallSwapAndFailedCall() public {
        bytes memory swapData = abi.encodeWithSelector(
            DEX_ROUTER.swapTo.selector,
            address(USDC),
            address(WETH),
            BASE_PROXY_USDC_BALANCE,
            address(PROXYCALL)
        );

        bytes memory callData = abi.encodeWithSelector(
            MOCK_DEPOSIT.deposit.selector,
            address(WETH),
            BASE_PROXY_USDC_BALANCE
        );

        vm.startPrank(CALLER);
        (address effTOut, uint256 effAOut, bool success) = PROXYCALL.call(
            USER,
            address(DEX_ROUTER),
            address(MOCK_DEPOSIT_ROUTER),
            address(USDC),
            address(WETH),
            BASE_ROUTER_WETH_BALANCE / 2,
            swapData,
            callData
        );
        vm.stopPrank();

        assertEq(effTOut, address(WETH), "Effective tokenOut should be WETH");
        assertEq(
            effAOut,
            BASE_ROUTER_WETH_BALANCE / 2,
            "Effective amountOut should be half of the router's WETH balance"
        );
        assertEq(success, false, "Operation should be not successful");
        assertEq(WETH.balanceOf(address(USER)), BASE_ROUTER_WETH_BALANCE / 2);
    }

    function testRevertCallWrongCaller() public {
        vm.startPrank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(GeniusErrors.InvalidCaller.selector)
        );
        PROXYCALL.call(
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
    }

    function testApproveTokenExecuteAndVerify() public {
        bytes memory swapData = abi.encodeWithSelector(
            DEX_ROUTER.swapTo.selector,
            address(USDC),
            address(WETH),
            BASE_PROXY_USDC_BALANCE,
            address(USER)
        );

        vm.startPrank(CALLER);
        uint256 amountOut = PROXYCALL.approveTokenExecuteAndVerify(
            address(USDC),
            address(DEX_ROUTER),
            swapData,
            address(WETH),
            BASE_ROUTER_WETH_BALANCE / 2,
            address(USER)
        );

        assertEq(amountOut, BASE_ROUTER_WETH_BALANCE / 2);
    }

    function testRevertApproveTokenExecuteAndVerifyIfFailedSwap() public {
        bytes memory swapData = abi.encodeWithSelector(
            DEX_ROUTER.swapTo.selector,
            address(USDC),
            address(WETH),
            BASE_PROXY_USDC_BALANCE + 1 ether,
            address(USER)
        );

        vm.startPrank(CALLER);

        vm.expectRevert(
            abi.encodeWithSelector(
                GeniusErrors.ExternalCallFailed.selector,
                address(DEX_ROUTER)
            )
        );

        PROXYCALL.approveTokenExecuteAndVerify(
            address(USDC),
            address(DEX_ROUTER),
            swapData,
            address(WETH),
            BASE_ROUTER_WETH_BALANCE / 2,
            address(USER)
        );

        vm.stopPrank();
        assertEq(USDC.balanceOf(address(PROXYCALL)), BASE_PROXY_USDC_BALANCE);
    }

    function testRevertApproveTokenExecuteAndVerifyIfUnexpectedAmountOut()
        public
    {
        bytes memory swapData = abi.encodeWithSelector(
            DEX_ROUTER.swapTo.selector,
            address(USDC),
            address(WETH),
            BASE_PROXY_USDC_BALANCE,
            address(USER)
        );

        vm.startPrank(CALLER);

        vm.expectRevert(
            abi.encodeWithSelector(
                GeniusErrors.InvalidAmountOut.selector,
                BASE_ROUTER_WETH_BALANCE / 2,
                BASE_ROUTER_WETH_BALANCE / 2 + 1 ether
            )
        );

        PROXYCALL.approveTokenExecuteAndVerify(
            address(USDC),
            address(DEX_ROUTER),
            swapData,
            address(WETH),
            BASE_ROUTER_WETH_BALANCE / 2 + 1 ether,
            address(USER)
        );
        vm.stopPrank();

        assertEq(USDC.balanceOf(address(PROXYCALL)), BASE_PROXY_USDC_BALANCE);
    }

    function testRevertApproveTokenExecuteAndVerifyIfWrongCaller() public {
        bytes memory swapData = abi.encodeWithSelector(
            DEX_ROUTER.swapTo.selector,
            address(USDC),
            address(WETH),
            BASE_PROXY_USDC_BALANCE,
            address(USER)
        );

        vm.startPrank(USER);

        vm.expectRevert(
            abi.encodeWithSelector(GeniusErrors.InvalidCaller.selector)
        );

        PROXYCALL.approveTokenExecuteAndVerify(
            address(USDC),
            address(DEX_ROUTER),
            swapData,
            address(WETH),
            BASE_ROUTER_WETH_BALANCE / 2 + 1 ether,
            address(USER)
        );
        vm.stopPrank();

        assertEq(USDC.balanceOf(address(PROXYCALL)), BASE_PROXY_USDC_BALANCE);
    }

    function testApproveTokenExecute() public {
        bytes memory swapData = abi.encodeWithSelector(
            DEX_ROUTER.swapTo.selector,
            address(USDC),
            address(WETH),
            BASE_PROXY_USDC_BALANCE,
            address(USER)
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

    function testRevertApproveTokenExecuteIfFailedSwap() public {
        bytes memory swapData = abi.encodeWithSelector(
            DEX_ROUTER.swapTo.selector,
            address(USDC),
            address(WETH),
            BASE_PROXY_USDC_BALANCE + 1 ether,
            address(USER)
        );

        vm.startPrank(CALLER);

        vm.expectRevert(
            abi.encodeWithSelector(
                GeniusErrors.ExternalCallFailed.selector,
                address(DEX_ROUTER)
            )
        );

        PROXYCALL.approveTokenExecute(
            address(USDC),
            address(DEX_ROUTER),
            swapData
        );

        vm.stopPrank();
        assertEq(USDC.balanceOf(address(PROXYCALL)), BASE_PROXY_USDC_BALANCE);
    }

    function testRevertApproveTokenExecuteWrongCaller() public {
        bytes memory swapData = abi.encodeWithSelector(
            DEX_ROUTER.swapTo.selector,
            address(USDC),
            address(WETH),
            BASE_PROXY_USDC_BALANCE,
            address(USER)
        );

        vm.startPrank(USER);

        vm.expectRevert(
            abi.encodeWithSelector(GeniusErrors.InvalidCaller.selector)
        );

        PROXYCALL.approveTokenExecute(
            address(USDC),
            address(DEX_ROUTER),
            swapData
        );
        vm.stopPrank();

        assertEq(USDC.balanceOf(address(PROXYCALL)), BASE_PROXY_USDC_BALANCE);
    }

    function testApproveTokensAndExecute() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(USDC);
        tokens[1] = address(WETH);

        bytes memory swapData = abi.encodeWithSelector(
            DEX_ROUTER.swapTo.selector,
            address(USDC),
            address(WETH),
            BASE_PROXY_USDC_BALANCE,
            address(USER)
        );

        vm.startPrank(CALLER);
        PROXYCALL.approveTokensAndExecute(
            tokens,
            address(DEX_ROUTER),
            swapData
        );
        vm.stopPrank();

        assertEq(WETH.balanceOf(USER), BASE_ROUTER_WETH_BALANCE / 2);
    }

    function testApproveTokensAndExecuteCanBeCalledBySelf() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(USDC);
        tokens[1] = address(WETH);

        address[] memory targets = new address[](1);
        bytes[] memory data = new bytes[](1);
        uint256[] memory values = new uint256[](1);

        targets[0] = address(PROXYCALL);
        data[0] = abi.encodeWithSelector(
            PROXYCALL.approveTokensAndExecute.selector,
            tokens,
            address(DEX_ROUTER),
            abi.encodeWithSelector(
                DEX_ROUTER.swapTo.selector,
                address(USDC),
                address(WETH),
                BASE_PROXY_USDC_BALANCE,
                address(USER)
            )
        );
        values[0] = 0;

        bytes memory transactions = _encodeTransactions(targets, values, data);

        vm.startPrank(CALLER);
        PROXYCALL.execute(address(PROXYCALL), transactions);
        vm.stopPrank();

        assertEq(WETH.balanceOf(USER), BASE_ROUTER_WETH_BALANCE / 2);
    }

    function testRevertApproveTokensAndExecuteIfTargetAddress0() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(USDC);
        tokens[1] = address(WETH);

        bytes memory swapData = abi.encodeWithSelector(
            DEX_ROUTER.swapTo.selector,
            address(USDC),
            address(WETH),
            BASE_PROXY_USDC_BALANCE,
            address(USER)
        );

        vm.startPrank(CALLER);
        vm.expectRevert(
            abi.encodeWithSelector(GeniusErrors.NonAddress0.selector)
        );
        PROXYCALL.approveTokensAndExecute(tokens, address(0), swapData);
        vm.stopPrank();
    }

    function testRevertApproveTokensAndExecuteIfTargetNotContract() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(USDC);
        tokens[1] = address(WETH);

        bytes memory swapData = abi.encodeWithSelector(
            DEX_ROUTER.swapTo.selector,
            address(USDC),
            address(WETH),
            BASE_PROXY_USDC_BALANCE,
            address(USER)
        );

        vm.startPrank(CALLER);
        vm.expectRevert(
            abi.encodeWithSelector(GeniusErrors.TargetIsNotContract.selector)
        );
        PROXYCALL.approveTokensAndExecute(tokens, USER, swapData);
        vm.stopPrank();
    }

    function testRevertApproveTokensAndExecuteIfExternalCallFailed() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(USDC);
        tokens[1] = address(WETH);

        bytes memory swapData = abi.encodeWithSelector(
            DEX_ROUTER.swapTo.selector,
            address(USDC),
            address(WETH),
            BASE_PROXY_USDC_BALANCE + 1 ether, // Try to swap more than available
            address(USER)
        );

        vm.startPrank(CALLER);
        vm.expectRevert(
            abi.encodeWithSelector(
                GeniusErrors.ExternalCallFailed.selector,
                address(DEX_ROUTER)
            )
        );
        PROXYCALL.approveTokensAndExecute(
            tokens,
            address(DEX_ROUTER),
            swapData
        );
        vm.stopPrank();
    }

    function testRevertApproveTokensAndExecuteIfUnauthorizedCaller() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(USDC);
        tokens[1] = address(WETH);

        bytes memory swapData = abi.encodeWithSelector(
            DEX_ROUTER.swapTo.selector,
            address(USDC),
            address(WETH),
            BASE_PROXY_USDC_BALANCE,
            address(USER)
        );

        vm.startPrank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(GeniusErrors.InvalidCaller.selector)
        );
        PROXYCALL.approveTokensAndExecute(
            tokens,
            address(DEX_ROUTER),
            swapData
        );
        vm.stopPrank();
    }

    function testApprovalsAreResetAfterExecution() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(USDC);
        tokens[1] = address(WETH);

        bytes memory swapData = abi.encodeWithSelector(
            DEX_ROUTER.swapTo.selector,
            address(USDC),
            address(WETH),
            BASE_PROXY_USDC_BALANCE,
            address(USER)
        );

        vm.startPrank(CALLER);
        PROXYCALL.approveTokensAndExecute(
            tokens,
            address(DEX_ROUTER),
            swapData
        );
        vm.stopPrank();

        // Check that approvals were reset to 0
        assertEq(USDC.allowance(address(PROXYCALL), address(DEX_ROUTER)), 0);
        assertEq(WETH.allowance(address(PROXYCALL), address(DEX_ROUTER)), 0);
    }

    function testTransferTokenAndExecute() public {
        bytes memory depositData = abi.encodeWithSelector(
            MOCK_DEPOSIT_ROUTER.depositBalance.selector,
            address(USDC)
        );

        vm.startPrank(CALLER);
        PROXYCALL.transferTokenAndExecute(
            address(USDC),
            address(MOCK_DEPOSIT_ROUTER),
            depositData
        );
        vm.stopPrank();

        // Verify the token was transferred and the deposit was successful
        assertEq(
            USDC.balanceOf(address(MOCK_DEPOSIT)),
            BASE_PROXY_USDC_BALANCE
        );
        assertEq(USDC.balanceOf(address(PROXYCALL)), 0);
    }

    function testTransferTokenAndExecuteCanBeCalledBySelf() public {
        address[] memory targets = new address[](1);
        bytes[] memory data = new bytes[](1);
        uint256[] memory values = new uint256[](1);

        bytes memory depositData = abi.encodeWithSelector(
            MOCK_DEPOSIT_ROUTER.depositBalance.selector,
            address(USDC)
        );

        targets[0] = address(PROXYCALL);
        data[0] = abi.encodeWithSelector(
            PROXYCALL.transferTokenAndExecute.selector,
            address(USDC),
            address(MOCK_DEPOSIT_ROUTER),
            depositData
        );
        values[0] = 0;

        bytes memory transactions = _encodeTransactions(targets, values, data);

        vm.startPrank(CALLER);
        PROXYCALL.execute(address(PROXYCALL), transactions);
        vm.stopPrank();

        assertEq(
            USDC.balanceOf(address(MOCK_DEPOSIT)),
            BASE_PROXY_USDC_BALANCE
        );
        assertEq(USDC.balanceOf(address(PROXYCALL)), 0);
    }

    function testRevertTransferTokenAndExecuteIfTargetAddress0() public {
        bytes memory depositData = abi.encodeWithSelector(
            MOCK_DEPOSIT.deposit.selector,
            address(USDC),
            BASE_PROXY_USDC_BALANCE
        );

        vm.startPrank(CALLER);
        vm.expectRevert(
            abi.encodeWithSelector(GeniusErrors.NonAddress0.selector)
        );
        PROXYCALL.transferTokenAndExecute(
            address(USDC),
            address(0),
            depositData
        );
        vm.stopPrank();
    }

    function testRevertTransferTokenAndExecuteIfTargetNotContract() public {
        bytes memory depositData = abi.encodeWithSelector(
            MOCK_DEPOSIT.deposit.selector,
            address(USDC),
            BASE_PROXY_USDC_BALANCE
        );

        vm.startPrank(CALLER);
        vm.expectRevert(
            abi.encodeWithSelector(GeniusErrors.TargetIsNotContract.selector)
        );
        PROXYCALL.transferTokenAndExecute(address(USDC), USER, depositData);
        vm.stopPrank();
    }

    function testRevertTransferTokenAndExecuteIfExternalCallFailed() public {
        // Try to deposit more than the contract has
        bytes memory depositData = abi.encodeWithSelector(
            MOCK_DEPOSIT.deposit.selector,
            address(USDC),
            BASE_PROXY_USDC_BALANCE + 1 ether
        );

        vm.startPrank(CALLER);
        vm.expectRevert(
            abi.encodeWithSelector(
                GeniusErrors.ExternalCallFailed.selector,
                address(MOCK_DEPOSIT)
            )
        );
        PROXYCALL.transferTokenAndExecute(
            address(USDC),
            address(MOCK_DEPOSIT),
            depositData
        );
        vm.stopPrank();

        assertEq(USDC.balanceOf(address(PROXYCALL)), BASE_PROXY_USDC_BALANCE);
    }

    function testTransferTokenAndExecuteWithValue() public {
        bytes memory depositData = abi.encodeWithSelector(
            MOCK_DEPOSIT_ROUTER.depositBalance.selector,
            address(USDC)
        );

        vm.deal(CALLER, 1 ether);

        vm.startPrank(CALLER);
        PROXYCALL.transferTokenAndExecute{value: 1 ether}(
            address(USDC),
            address(MOCK_DEPOSIT_ROUTER),
            depositData
        );
        vm.stopPrank();

        assertEq(
            USDC.balanceOf(address(MOCK_DEPOSIT)),
            BASE_PROXY_USDC_BALANCE
        );
        assertEq(USDC.balanceOf(address(PROXYCALL)), 0);
        assertEq(address(MOCK_DEPOSIT_ROUTER).balance, 1 ether);
    }

    function testTransferTokensAndExecute() public {
        // Set up test tokens array
        address[] memory tokens = new address[](2);
        tokens[0] = address(USDC);
        tokens[1] = address(WETH);

        // Give some WETH to ProxyCall for testing multiple tokens
        deal(address(WETH), address(PROXYCALL), 10 ether);

        bytes memory depositData = abi.encodeWithSelector(
            MOCK_DEPOSIT_ROUTER.depositBalances.selector,
            tokens
        );

        vm.startPrank(CALLER);
        PROXYCALL.transferTokensAndExecute(
            tokens,
            address(MOCK_DEPOSIT_ROUTER),
            depositData
        );
        vm.stopPrank();

        // Verify the tokens were transferred and the deposit was successful
        assertEq(
            USDC.balanceOf(address(MOCK_DEPOSIT)),
            BASE_PROXY_USDC_BALANCE,
            "USDC should be transferred to deposit contract"
        );
        assertEq(
            WETH.balanceOf(address(MOCK_DEPOSIT)),
            10 ether,
            "WETH should be transferred to deposit contract"
        );
        assertEq(
            USDC.balanceOf(address(PROXYCALL)),
            0,
            "PROXYCALL should have 0 USDC balance"
        );
        assertEq(
            WETH.balanceOf(address(PROXYCALL)),
            0,
            "PROXYCALL should have 0 WETH balance"
        );
    }

    function testTransferTokensAndExecuteWithEmptyBalance() public {
        // Set up test tokens array with a token that has 0 balance
        address[] memory tokens = new address[](2);
        tokens[0] = address(USDC);
        tokens[1] = address(WETH); // PROXYCALL has 0 WETH balance

        bytes memory depositData = abi.encodeWithSelector(
            MOCK_DEPOSIT_ROUTER.depositBalance.selector,
            address(USDC)
        );

        vm.startPrank(CALLER);
        PROXYCALL.transferTokensAndExecute(
            tokens,
            address(MOCK_DEPOSIT_ROUTER),
            depositData
        );
        vm.stopPrank();

        // Verify only non-zero balances were transferred
        assertEq(
            USDC.balanceOf(address(MOCK_DEPOSIT)),
            BASE_PROXY_USDC_BALANCE,
            "USDC should be transferred to deposit contract"
        );
        assertEq(
            WETH.balanceOf(address(MOCK_DEPOSIT)),
            0,
            "No WETH should be transferred when balance is 0"
        );
    }

    function testTransferTokensAndExecuteCanBeCalledBySelf() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(USDC);
        tokens[1] = address(WETH);

        // Give some WETH to ProxyCall for testing
        deal(address(WETH), address(PROXYCALL), 1 ether);

        address[] memory targets = new address[](1);
        bytes[] memory data = new bytes[](1);
        uint256[] memory values = new uint256[](1);

        bytes memory depositData = abi.encodeWithSelector(
            MOCK_DEPOSIT_ROUTER.depositBalances.selector,
            tokens
        );

        targets[0] = address(PROXYCALL);
        data[0] = abi.encodeWithSelector(
            PROXYCALL.transferTokensAndExecute.selector,
            tokens,
            address(MOCK_DEPOSIT_ROUTER),
            depositData
        );
        values[0] = 0;

        bytes memory transactions = _encodeTransactions(targets, values, data);

        vm.startPrank(CALLER);
        PROXYCALL.execute(address(PROXYCALL), transactions);
        vm.stopPrank();

        assertEq(
            USDC.balanceOf(address(MOCK_DEPOSIT)),
            BASE_PROXY_USDC_BALANCE,
            "USDC should be transferred to deposit contract"
        );
        assertEq(
            WETH.balanceOf(address(MOCK_DEPOSIT)),
            1 ether,
            "WETH should be transferred to deposit contract"
        );
        assertEq(USDC.balanceOf(address(PROXYCALL)), 0);
        assertEq(WETH.balanceOf(address(PROXYCALL)), 0);
    }

    function testTransferTokensAndExecuteWithValue() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(USDC);
        tokens[1] = address(WETH);

        // Give some WETH to ProxyCall for testing
        deal(address(WETH), address(PROXYCALL), 1 ether);

        bytes memory depositData = abi.encodeWithSelector(
            MOCK_DEPOSIT_ROUTER.depositBalances.selector,
            tokens
        );

        vm.deal(CALLER, 1 ether);

        vm.startPrank(CALLER);
        PROXYCALL.transferTokensAndExecute{value: 1 ether}(
            tokens,
            address(MOCK_DEPOSIT_ROUTER),
            depositData
        );
        vm.stopPrank();

        assertEq(
            USDC.balanceOf(address(MOCK_DEPOSIT)),
            BASE_PROXY_USDC_BALANCE,
            "USDC should be transferred to deposit contract"
        );
        assertEq(
            WETH.balanceOf(address(MOCK_DEPOSIT)),
            1 ether,
            "WETH should be transferred to deposit contract"
        );
        assertEq(USDC.balanceOf(address(PROXYCALL)), 0);
        assertEq(WETH.balanceOf(address(PROXYCALL)), 0);
        assertEq(
            address(MOCK_DEPOSIT_ROUTER).balance,
            1 ether,
            "ETH value should be transferred"
        );
    }

    function testRevertTransferTokensAndExecuteIfTargetAddress0() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(USDC);
        tokens[1] = address(WETH);

        bytes memory depositData = abi.encodeWithSelector(
            MOCK_DEPOSIT.deposit.selector,
            address(USDC),
            BASE_PROXY_USDC_BALANCE
        );

        vm.startPrank(CALLER);
        vm.expectRevert(
            abi.encodeWithSelector(GeniusErrors.NonAddress0.selector)
        );
        PROXYCALL.transferTokensAndExecute(tokens, address(0), depositData);
        vm.stopPrank();
    }

    function testRevertTransferTokensAndExecuteIfTargetNotContract() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(USDC);
        tokens[1] = address(WETH);

        bytes memory depositData = abi.encodeWithSelector(
            MOCK_DEPOSIT.deposit.selector,
            address(USDC),
            BASE_PROXY_USDC_BALANCE
        );

        vm.startPrank(CALLER);
        vm.expectRevert(
            abi.encodeWithSelector(GeniusErrors.TargetIsNotContract.selector)
        );
        PROXYCALL.transferTokensAndExecute(tokens, USER, depositData);
        vm.stopPrank();
    }

    function testRevertTransferTokensAndExecuteIfExternalCallFailed() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(USDC);
        tokens[1] = address(WETH);

        // Try to deposit more than the contract has
        bytes memory depositData = abi.encodeWithSelector(
            MOCK_DEPOSIT.deposit.selector,
            address(USDC),
            BASE_PROXY_USDC_BALANCE + 1 ether
        );

        vm.startPrank(CALLER);
        vm.expectRevert(
            abi.encodeWithSelector(
                GeniusErrors.ExternalCallFailed.selector,
                address(MOCK_DEPOSIT)
            )
        );
        PROXYCALL.transferTokensAndExecute(
            tokens,
            address(MOCK_DEPOSIT),
            depositData
        );
        vm.stopPrank();

        // Verify no tokens were transferred
        assertEq(
            USDC.balanceOf(address(PROXYCALL)),
            BASE_PROXY_USDC_BALANCE,
            "PROXYCALL should retain USDC balance after failed call"
        );
    }

    function testRevertTransferTokensAndExecuteIfUnauthorizedCaller() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(USDC);
        tokens[1] = address(WETH);

        bytes memory depositData = abi.encodeWithSelector(
            MOCK_DEPOSIT_ROUTER.depositBalance.selector,
            address(USDC)
        );

        vm.startPrank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(GeniusErrors.InvalidCaller.selector)
        );
        PROXYCALL.transferTokensAndExecute(
            tokens,
            address(MOCK_DEPOSIT_ROUTER),
            depositData
        );
        vm.stopPrank();
    }

    // ============ USDT TESTS ============
    
    // Test USDT approval behavior with single token
    function testApproveTokenExecuteWithUSDT() public {
        // Deploy mock USDT-like token
        MockERC20LikeUSDT usdt = new MockERC20LikeUSDT();
        
        // Give USDT to ProxyCall
        deal(address(usdt), address(PROXYCALL), 1000 * 10**6); // 1000 USDT (6 decimals)
        
        bytes memory swapData = abi.encodeWithSelector(
            DEX_ROUTER.swapTo.selector,
            address(usdt),
            address(WETH),
            500 * 10**6, // 500 USDT
            address(USER)
        );

        vm.startPrank(CALLER);
        PROXYCALL.approveTokenExecute(
            address(usdt),
            address(DEX_ROUTER),
            swapData
        );
        vm.stopPrank();

        // Verify USDT was transferred to DEX router
        assertEq(usdt.balanceOf(address(DEX_ROUTER)), 500 * 10**6);
        
        // Verify approval was reset to 0
        assertEq(usdt.allowance(address(PROXYCALL), address(DEX_ROUTER)), 0);
    }

    // Test USDT approval behavior with multiple tokens
    function testApproveTokensAndExecuteWithUSDT() public {
        // Deploy mock USDT-like token
        MockERC20LikeUSDT usdt = new MockERC20LikeUSDT();
        
        // Give USDT to ProxyCall
        deal(address(usdt), address(PROXYCALL), 1000 * 10**6); // 1000 USDT (6 decimals)
        
        address[] memory tokens = new address[](2);
        tokens[0] = address(usdt);
        tokens[1] = address(USDC);

        bytes memory swapData = abi.encodeWithSelector(
            DEX_ROUTER.swapTo.selector,
            address(usdt),
            address(WETH),
            500 * 10**6, // 500 USDT
            address(USER)
        );

        vm.startPrank(CALLER);
        PROXYCALL.approveTokensAndExecute(
            tokens,
            address(DEX_ROUTER),
            swapData
        );
        vm.stopPrank();

        // Verify USDT was transferred to DEX router
        assertEq(usdt.balanceOf(address(DEX_ROUTER)), 500 * 10**6);
        
        // Verify approvals were reset to 0
        assertEq(usdt.allowance(address(PROXYCALL), address(DEX_ROUTER)), 0);
        assertEq(USDC.allowance(address(PROXYCALL), address(DEX_ROUTER)), 0);
    }

    // Test USDT approval and verification
    function testApproveTokenExecuteAndVerifyWithUSDT() public {
        // Deploy mock USDT-like token
        MockERC20LikeUSDT usdt = new MockERC20LikeUSDT();
        
        // Give USDT to ProxyCall
        deal(address(usdt), address(PROXYCALL), 1000 * 10**6); // 1000 USDT (6 decimals)
        
        bytes memory swapData = abi.encodeWithSelector(
            DEX_ROUTER.swapTo.selector,
            address(usdt),
            address(WETH),
            500 * 10**6, // 500 USDT
            address(USER)
        );

        vm.startPrank(CALLER);
        uint256 amountOut = PROXYCALL.approveTokenExecuteAndVerify(
            address(usdt),
            address(DEX_ROUTER),
            swapData,
            address(WETH),
            BASE_ROUTER_WETH_BALANCE / 4, // Expect half of what we swap
            address(USER)
        );
        vm.stopPrank();

        assertEq(amountOut, BASE_ROUTER_WETH_BALANCE / 2);
        assertEq(usdt.allowance(address(PROXYCALL), address(DEX_ROUTER)), 0);
    }

    // Test USDT transfer and execute
    function testTransferTokenAndExecuteWithUSDT() public {
        // Deploy mock USDT-like token
        MockERC20LikeUSDT usdt = new MockERC20LikeUSDT();
        
        // Give USDT to ProxyCall
        deal(address(usdt), address(PROXYCALL), 1000 * 10**6); // 1000 USDT (6 decimals)
        
        bytes memory depositData = abi.encodeWithSelector(
            MOCK_DEPOSIT_ROUTER.depositBalance.selector,
            address(usdt)
        );

        vm.startPrank(CALLER);
        PROXYCALL.transferTokenAndExecute(
            address(usdt),
            address(MOCK_DEPOSIT_ROUTER),
            depositData
        );
        vm.stopPrank();

        // Verify USDT was transferred to deposit contract
        assertEq(usdt.balanceOf(address(MOCK_DEPOSIT)), 1000 * 10**6);
        assertEq(usdt.balanceOf(address(PROXYCALL)), 0);
    }

    // Test USDT transfer tokens and execute
    function testTransferTokensAndExecuteWithUSDT() public {
        // Deploy mock USDT-like token
        MockERC20LikeUSDT usdt = new MockERC20LikeUSDT();
        
        // Give USDT to ProxyCall
        deal(address(usdt), address(PROXYCALL), 1000 * 10**6); // 1000 USDT (6 decimals)
        
        address[] memory tokens = new address[](2);
        tokens[0] = address(usdt);
        tokens[1] = address(USDC);

        bytes memory depositData = abi.encodeWithSelector(
            MOCK_DEPOSIT_ROUTER.depositBalances.selector,
            tokens
        );

        vm.startPrank(CALLER);
        PROXYCALL.transferTokensAndExecute(
            tokens,
            address(MOCK_DEPOSIT_ROUTER),
            depositData
        );
        vm.stopPrank();

        // Verify both tokens were transferred
        assertEq(usdt.balanceOf(address(MOCK_DEPOSIT)), 1000 * 10**6);
        assertEq(USDC.balanceOf(address(MOCK_DEPOSIT)), BASE_PROXY_USDC_BALANCE);
        assertEq(usdt.balanceOf(address(PROXYCALL)), 0);
        assertEq(USDC.balanceOf(address(PROXYCALL)), 0);
    }

    // Test USDT call function with swap
    function testCallWithUSDTSwap() public {
        // Deploy mock USDT-like token
        MockERC20LikeUSDT usdt = new MockERC20LikeUSDT();
        
        // Give USDT to ProxyCall
        deal(address(usdt), address(PROXYCALL), 1000 * 10**6); // 1000 USDT (6 decimals)
        
        bytes memory data = abi.encodeWithSelector(
            DEX_ROUTER.swapTo.selector,
            address(usdt),
            address(WETH),
            500 * 10**6, // 500 USDT
            USER
        );

        vm.startPrank(CALLER);
        (address effTOut, uint256 effAOut, bool success) = PROXYCALL.call(
            USER,
            address(DEX_ROUTER),
            address(0),
            address(usdt),
            address(WETH),
            BASE_ROUTER_WETH_BALANCE / 4,
            data,
            ""
        );
        vm.stopPrank();

        assertEq(effTOut, address(WETH), "Effective tokenOut should be WETH");
        assertEq(effAOut, BASE_ROUTER_WETH_BALANCE / 2, "Effective amountOut should be half of the router's WETH balance");
        assertEq(success, true, "Operation should be successful");
        assertEq(WETH.balanceOf(USER), BASE_ROUTER_WETH_BALANCE / 2);
        
        // Verify USDT approval was reset
        assertEq(usdt.allowance(address(PROXYCALL), address(DEX_ROUTER)), 0);
    }

    // Test USDT call function with failed swap
    function testCallWithUSDTFailedSwap() public {
        // Deploy mock USDT-like token
        MockERC20LikeUSDT usdt = new MockERC20LikeUSDT();
        
        // Give USDT to ProxyCall
        deal(address(usdt), address(PROXYCALL), 1000 * 10**6); // 1000 USDT (6 decimals)
        
        bytes memory data = abi.encodeWithSelector(
            DEX_ROUTER.swapTo.selector,
            address(usdt),
            address(WETH),
            2000 * 10**6, // Try to swap more than available
            USER
        );

        vm.startPrank(CALLER);
        (address effTOut, uint256 effAOut, bool success) = PROXYCALL.call(
            USER,
            address(DEX_ROUTER),
            address(0),
            address(usdt),
            address(WETH),
            BASE_ROUTER_WETH_BALANCE / 2,
            data,
            ""
        );
        vm.stopPrank();

        assertEq(effTOut, address(usdt), "Should fall back to USDT");
        assertEq(effAOut, 1000 * 10**6, "Should return original USDT amount");
        assertEq(success, false, "Operation should fail");
        assertEq(usdt.balanceOf(USER), 1000 * 10**6, "User should receive USDT back");
    }

    // Test USDT with real USDT address on Avalanche
    function testApproveTokenExecuteWithRealUSDT() public {
        // Use real USDT on Avalanche
        ERC20 realUSDT = ERC20(0x9702230A8Ea53601f5cD2dc00fDBc13d4dF4A8c7);
        
        // Give real USDT to ProxyCall
        deal(address(realUSDT), address(PROXYCALL), 1000 * 10**6); // 1000 USDT (6 decimals)
        
        bytes memory swapData = abi.encodeWithSelector(
            DEX_ROUTER.swapTo.selector,
            address(realUSDT),
            address(WETH),
            500 * 10**6, // 500 USDT
            address(USER)
        );

        vm.startPrank(CALLER);
        PROXYCALL.approveTokenExecute(
            address(realUSDT),
            address(DEX_ROUTER),
            swapData
        );
        vm.stopPrank();

        // Verify USDT was transferred to DEX router
        assertEq(realUSDT.balanceOf(address(DEX_ROUTER)), 500 * 10**6);
        
        // Verify approval was reset to 0
        assertEq(realUSDT.allowance(address(PROXYCALL), address(DEX_ROUTER)), 0);
    }

    // Test multiple USDT approvals in sequence
    function testMultipleUSDTApprovals() public {
        // Deploy mock USDT-like token
        MockERC20LikeUSDT usdt = new MockERC20LikeUSDT();
        
        // Give USDT to ProxyCall
        deal(address(usdt), address(PROXYCALL), 1000 * 10**6); // 1000 USDT (6 decimals)
        
        bytes memory swapData1 = abi.encodeWithSelector(
            DEX_ROUTER.swapTo.selector,
            address(usdt),
            address(WETH),
            200 * 10**6, // 200 USDT
            address(USER)
        );

        bytes memory swapData2 = abi.encodeWithSelector(
            DEX_ROUTER.swapTo.selector,
            address(usdt),
            address(WETH),
            300 * 10**6, // 300 USDT
            address(USER)
        );

        vm.startPrank(CALLER);
        
        // First approval and swap
        PROXYCALL.approveTokenExecute(
            address(usdt),
            address(DEX_ROUTER),
            swapData1
        );
        
        // Second approval and swap (should work because approval was reset)
        PROXYCALL.approveTokenExecute(
            address(usdt),
            address(DEX_ROUTER),
            swapData2
        );
        
        vm.stopPrank();

        // Verify total USDT transferred
        assertEq(usdt.balanceOf(address(DEX_ROUTER)), 500 * 10**6);
        
        // Verify approval was reset to 0 after each operation
        assertEq(usdt.allowance(address(PROXYCALL), address(DEX_ROUTER)), 0);
    }

    // ============ END USDT TESTS ============

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
