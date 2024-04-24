// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import {Test, console} from "forge-std/Test.sol";

import {GeniusPool} from "../src/GeniusPool.sol";
import {GeniusVault} from "../src/GeniusVault.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IStargateRouter} from "../src/interfaces/IStargateRouter.sol";


contract GeniusPoolTest is Test {
    uint256 avalanche;
    string private rpc = vm.envString("AVALANCHE_RPC_URL");

    uint256 sourceChainId = 106; // avalanche
    uint256 targetChainId = 101; // ethereum

    uint256 sourcePoolId = 1;
    uint256 targetPoolId = 1;

    address owner;
    address trader;
    address orchestrator;

    ERC20 public usdc;
    IStargateRouter public stargateRouter;

    GeniusPool public geniusPool;
    GeniusVault public geniusVault;

    function setUp() public {
        avalanche = vm.createFork(rpc);
        vm.selectFork(avalanche);
        assertEq(vm.activeFork(), avalanche);

        owner = makeAddr("owner");
        trader = makeAddr("trader");
        orchestrator = makeAddr("orchestrator");

        usdc = ERC20(0x1205f31718499dBf1fCa446663B532Ef87481fe1); // USDC on Avalanche
        stargateRouter = IStargateRouter(0x45A01E4e04F14f7A4a6702c74187c5F6222033cd); // Stargate Router on Avalanche

        vm.startPrank(owner);
        geniusPool = new GeniusPool(address(usdc), address(stargateRouter), owner);

        console.log("Genius Pool Owner: %s", geniusPool.owner());

        vm.startPrank(owner);
        geniusVault = new GeniusVault(address(usdc));

        console.log("Genius Vault Owner: %s", geniusVault.owner());

        vm.startPrank(0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38);
        geniusVault.initialize(address(geniusPool));

        vm.startPrank(owner);
        geniusPool.initialize(address(geniusVault));

        geniusPool.addOrchestrator(orchestrator);
        assertEq(geniusPool.orchestrator(orchestrator), true);

        deal(address(usdc), trader, 1_000 ether);
    }

}