// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {OrchestrableERC20} from "./mocks/OrchestrableERC20.sol";

// forge test -vvv --tx-origin 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38
contract OrchestrableTest is Test {
    OrchestrableERC20 public orchestrableERC20;
    address public orchestrator = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;
    address public owner;

    function setUp() public {
        owner = makeAddr("owner");

        orchestrableERC20 = new OrchestrableERC20(owner);
    }

    function testAddOrchestrator() public {
        vm.prank(owner);
        orchestrableERC20.addOrchestrator(orchestrator);
        assertEq(orchestrableERC20.orchestrator(orchestrator), true);
    }

    function testRemoveOrchestrator() public {
        vm.prank(owner);
        orchestrableERC20.addOrchestrator(orchestrator);
        assertEq(orchestrableERC20.orchestrator(orchestrator), true);

        vm.prank(owner);
        orchestrableERC20.removeOrchestrator(orchestrator);
        assertEq(orchestrableERC20.orchestrator(orchestrator), false);
    }

    function testMintAsOrchestrator() public {
        vm.prank(owner);
        orchestrableERC20.addOrchestrator(orchestrator);
        assertEq(orchestrableERC20.orchestrator(orchestrator), true);

        vm.prank(orchestrator);
        orchestrableERC20.mint(orchestrator, 1000);

        assertEq(orchestrableERC20.balanceOf(orchestrator), 1000);
    }

    function testMintExpectRevertWithoutOrchestrator() public {
        vm.prank(owner);
        orchestrableERC20.addOrchestrator(orchestrator);
        assertEq(orchestrableERC20.orchestrator(orchestrator), true);

        vm.prank(owner);
        orchestrableERC20.mint(orchestrator, 1000);
    }
}
