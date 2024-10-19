// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {GeniusVault} from "../../src/GeniusVault.sol";

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
    bytes32 constant ORCHESTRATOR_ROLE = keccak256("ORCHESTRATOR_ROLE");

    /**
     * @dev Executes the deployment of the GeniusVault contract.
     */
    // COMMAND: forge script script/utility/AddOrchestrator.s.sol:AddOrchestrator --rpc-url $POLYGON_RPC_URL --broadcast --verify -vvvv --via-ir
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        GeniusVault geniusVault = GeniusVault(
            payable(vm.envAddress("GENIUS_VAULT_ADDRESS"))
        );

        address[] memory orchestrators = new address[](5);
        orchestrators[0] = 0x17cC1e3AF40C88B235d9837990B8ad4D7C06F5cc;
        orchestrators[1] = 0x4102b4144e9EFb8Cb0D7dc4A3fD8E65E4A8b8fD0;
        orchestrators[2] = 0x90B29aF53D2bBb878cAe1952B773A307330393ef;
        orchestrators[3] = 0x7e5E0712c627746a918ae2015e5bfAB51c86dA26;
        orchestrators[4] = 0x5975fBa1186116168C479bb21Bb335f02D504CFB;

        for (uint i = 0; i < orchestrators.length; i++) {
            geniusVault.grantRole(ORCHESTRATOR_ROLE, orchestrators[i]);
            console.log("Orchestrator added to GeniusVault:", orchestrators[i]);
        }

        console.log("All orchestrators added to GeniusVault");

        vm.stopBroadcast();
    }
}
