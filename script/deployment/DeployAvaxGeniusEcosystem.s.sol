// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";

import {GeniusExecutor} from "../../src/GeniusExecutor.sol";
import {GeniusPool} from "../../src/GeniusPool.sol";
import {GeniusVault} from "../../src/GeniusVault.sol";
import {GeniusActions} from "../../src/GeniusActions.sol";

/**
 * @title DeployAvaxGeniusEcosystem
 * @dev A contract for deploying the GeniusExecutor contract.
        Deployment commands:
        `source .env` // Load environment variables
        AVALANCHE: forge script script/deployment/DeployAvaxGeniusEcosystem.s.sol:DeployAvaxGeniusEcosystem --rpc-url $AVALANCHE_RPC_URL --broadcast -vvvv --via-ir
 */
contract DeployAvaxGeniusEcosystem is Script {
    address public constant stableAddress = 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E;
    address public constant bridgeAddress = 0x45A01E4e04F14f7A4a6702c74187c5F6222033cd;
    address public constant permit2Address = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    address public constant owner = 0x5CC11Ef1DE86c5E00259a463Ac3F3AE1A0fA2909;
    address public constant admin = 0x6192A053B05942e9D7EB98e3b2146283aD559e62;

    GeniusPool public geniusPool;
    GeniusVault public geniusVault;
    GeniusExecutor public geniusExecutor;
    GeniusActions public geniusActions;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        // geniusActions = new GeniusActions(admin);
        geniusPool = new GeniusPool(stableAddress, bridgeAddress, owner);
        geniusVault = new GeniusVault(stableAddress);
        geniusExecutor = new GeniusExecutor(permit2Address, address(geniusPool));

        // Initialize the contracts
        geniusPool.initialize(address(geniusVault));
        geniusVault.initialize(address(geniusPool));

        // Add orchestrators
        geniusPool.addOrchestrator(0x17cC1e3AF40C88B235d9837990B8ad4D7C06F5cc);
        geniusPool.addOrchestrator(0x4102b4144e9EFb8Cb0D7dc4A3fD8E65E4A8b8fD0);
        geniusPool.addOrchestrator(0x90B29aF53D2bBb878cAe1952B773A307330393ef);
        geniusPool.addOrchestrator(0x7e5E0712c627746a918ae2015e5bfAB51c86dA26);
        geniusPool.addOrchestrator(0x5975fBa1186116168C479bb21Bb335f02D504CFB);


        console.log("GeniusPool deployed at: ", address(geniusPool));
        console.log("GeniusVault deployed at: ", address(geniusVault));
        console.log("GeniusExecutor deployed at: ", address(geniusExecutor));
    }
}
