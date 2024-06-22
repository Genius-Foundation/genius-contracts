// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {GeniusPool} from "../../src/GeniusPool.sol";

/**
 * @title AddOrchestrator
 * @dev A contract for deploying the GeniusVault contract.
        Deployment command: 
        AVALANCHE: forge script script/utility/AddOrchestrator.s.sol:AddOrchestrator --rpc-url $AVALANCHE_RPC_URL --broadcast --verify -vvvv --via-ir
        BASE: forge script script/utility/AddOrchestrator.s.sol:AddOrchestrator --rpc-url $BASE_RPC_URL --broadcast --verify -vvvv --via-ir
        ARBITRUM: forge script script/utility/AddOrchestrator.s.sol:AddOrchestrator --rpc-url $ARBITRUM_RPC_URL --broadcast --verify -vvvv --via-ir
        OPTIMISM: forge script script/utility/AddOrchestrator.s.sol:AddOrchestrator --rpc-url $OPTIMISM_RPC_URL --broadcast --verify -vvvv --via-ir
        FANTOM: forge script script/utility/AddOrchestrator.s.sol:AddOrchestrator --rpc-url $FANTOM_RPC_URL --broadcast --verify -vvvv --via-ir
        POLYGON: forge script script/utility/AddOrchestrator.s.sol:AddOrchestrator --rpc-url $POLYGON_RPC_URL --broadcast --verify -vvvv --via-ir
        BSC: forge script script/utility/AddOrchestrator.s.sol:AddOrchestrator --rpc-url $BSC_RPC_URL --broadcast --verify -vvvv --via-ir
 */
contract AddOrchestrator is Script {

    /**
     * @dev Executes the deployment of the GeniusVault contract.
     */

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        GeniusPool geniusPool = GeniusPool(0x2789E39123D8AC259D7d5B5f84384B3a17b9145A);

        // Add orchestrator
        geniusPool.addOrchestrator(0xB4Ea547b917763A12e640eA52a77eaba81F2068a);

        console.log("Orchestrator added to GeniusPool");
    }
}