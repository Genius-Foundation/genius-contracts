// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.4;

// import {Test, console} from "forge-std/Test.sol";

// import {GeniusVault} from "../src/GeniusVault.sol";
// import {TestERC20} from "../src/TestERC20.sol";
// import {Permit2} from "permit2/Permit2.sol";

// contract GeniusVaultTest is Test {
//     address public fakeOwner = makeAddr("owner");
//     address public orchestrator = makeAddr("orchestrator");
//     address public trader = makeAddr("trader");

//     uint256 public amount = 1000 ether;

//     TestERC20 public testERC20 = new TestERC20();
//     GeniusVault public geniusVault = new GeniusVault(address(testERC20));
//     TestPermit public testPermit = new Permit2();

//     function getPermit(address owner, uint256 amount, address spender) private returns (IAllowanceTransfer.PermitSingle memory, bytes memory) {

//         uint256[] memory allowanceDetils = testPermit.allowance(owner, address(testERC20), address(geniusVault));
//         uint256 nonce = allowanceDetils[0];

//         IAllowanceTransfer.PermitSingle memory permit = IAllowanceTransfer.PermitSingle({
//             details: IAllowanceTransfer.PermitDetails({
//                 token: address(testERC20),
//                 amount: amount,
//                 expiration: block.timestamp + 30 seconds,
//                 nonce: nonce
//             }),
//             spender: spender
//         });

//         return permit
//     }

//     function test_constructor() view public {
//         assertEq(geniusVault.owner(), address(this));
//     }

//     function test_add_orchestrator() public {
//         geniusVault.addOrchestrator(address(orchestrator));
//         assertEq(geniusVault.isOrchestrator(address(orchestrator)), 1);
//     }

//     function test_add_orchestrator_without_owner() public {
//         vm.prank(fakeOwner);
//         vm.expectRevert();
//         geniusVault.addOrchestrator(address(orchestrator));
//     }

//     function test_remove_orchestrator() public {
//         geniusVault.addOrchestrator(address(orchestrator));
//         assertEq(geniusVault.isOrchestrator(address(orchestrator)), 1);

//         geniusVault.removeOrchestrator(address(orchestrator));
//         assertEq(geniusVault.isOrchestrator(address(orchestrator)), 0);
//     }

//     function test_remove_orchestrator_without_owner() public {
//         geniusVault.addOrchestrator(address(orchestrator));
//         assertEq(geniusVault.isOrchestrator(address(orchestrator)), 1);

//         vm.prank(fakeOwner);
//         vm.expectRevert();
//         geniusVault.removeOrchestrator(address(orchestrator));
//     }

//     function test_deposit_with_trader_without_matching_msg_sender() public {
//         vm.expectRevert();
//         geniusVault.addLiquidity(address(trader), amount);
//     }

//     function test_deposit_with_trader_with_matching_msg_sender() public {
//         testERC20.approve(address(geniusVault), amount);
//         geniusVault.addLiquidity(address(this), amount);
//         assertEq(testERC20.balanceOf(address(geniusVault)), amount);
//     }

//     function test_deposit_with_orchestrator() public {
//         geniusVault.addOrchestrator(address(orchestrator));

//         assertEq(geniusVault.isOrchestrator(address(orchestrator)), 1);

//         testERC20.transfer(address(orchestrator), amount);

//         vm.prank(orchestrator);
//         testERC20.approve(address(geniusVault), amount);

//         vm.prank(orchestrator);
//         geniusVault.addLiquidity(address(trader), amount);
//         assertEq(testERC20.balanceOf(address(geniusVault)), amount);
//     }

//     function test_deposit_without_orchestrator() public {
//         testERC20.approve(address(geniusVault), amount);
//         vm.expectRevert();
//         geniusVault.addLiquidity(address(trader), amount);
//     }

//     function test_withdraw_without_orchestrator() public {
//         geniusVault.addOrchestrator(address(this));
//         testERC20.approve(address(geniusVault), amount);
//         geniusVault.addLiquidity(address(trader), amount);

//         assertEq(testERC20.balanceOf(address(geniusVault)), amount);

//         vm.expectRevert();
//         geniusVault.removeLiquidity(address(trader), amount);
//     }

//     function test_withdraw_with_orchestrator() public {
//         geniusVault.addOrchestrator(address(this));
//         testERC20.approve(address(geniusVault), amount);
//         geniusVault.addLiquidity(address(trader), amount);

//         assertEq(testERC20.balanceOf(address(geniusVault)), amount);

//         geniusVault.removeLiquidity(address(trader), amount - 1);
//         assertEq(testERC20.balanceOf(address(geniusVault)), 1);
//     }

//     function test_withdraw_with_orchestrator_with_insufficient_balance() public {
//         geniusVault.addOrchestrator(address(this));
//         testERC20.approve(address(geniusVault), amount);
//         geniusVault.addLiquidity(address(trader), amount);

//         assertEq(testERC20.balanceOf(address(geniusVault)), amount);

//         vm.expectRevert();
//         geniusVault.removeLiquidity(address(trader), amount);
//     }
// }