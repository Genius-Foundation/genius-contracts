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

        PROXYCALL = new GeniusProxyCall(ADMIN, new address[](0));
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
            MOCK_DEPOSIT.deposit.selector,
            address(USDC),
            BASE_PROXY_USDC_BALANCE
        );

        vm.startPrank(CALLER);
        (address effTOut, uint256 effAOut, bool success) = PROXYCALL.call(
            USER,
            address(0),
            address(MOCK_DEPOSIT),
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

        PROXYCALL.approveTokenExecute(address(USDC), address(DEX_ROUTER), swapData);
        vm.stopPrank();

        assertEq(USDC.balanceOf(address(PROXYCALL)), BASE_PROXY_USDC_BALANCE);
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
