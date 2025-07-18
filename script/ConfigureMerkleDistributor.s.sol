// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {BaseScriptContext} from "./utils/BaseScriptContext.sol";
import {FeeCollector} from "../src/fees/FeeCollector.sol";
import {MerkleDistributor} from "../src/distributor/MerkleDistributor.sol";

/**
 * @title ConfigureMerkleDistributor
 * @dev A contract for configuring the MerkleDistributor integration with FeeCollector.
 *      This script will:
 *      1. Grant the DISTRIBUTOR_ROLE to a specific address on the FeeCollector
 *      2. Grant the DISTRIBUTOR_ROLE to the FeeCollector on the MerkleDistributor
 *      
 *      Deployment commands:
 *      `source .env` // Load environment variables
 *      ETHEREUM: source .env; forge script script/ConfigureMerkleDistributor.s.sol:ConfigureMerkleDistributor --rpc-url $ETHEREUM_RPC_URL --broadcast -vvvv --via-ir
 *      POLYGON: source .env; forge script script/ConfigureMerkleDistributor.s.sol:ConfigureMerkleDistributor --rpc-url $POLYGON_RPC_URL --broadcast -vvvv --via-ir
 *      BASE: source .env; forge script script/ConfigureMerkleDistributor.s.sol:ConfigureMerkleDistributor --rpc-url $BASE_RPC_URL --broadcast -vvvv --via-ir
 */
contract ConfigureMerkleDistributor is BaseScriptContext {
    // The address that will receive the DISTRIBUTOR_ROLE on FeeCollector
    address public constant DISTRIBUTOR_ADDRESS = 0xbeef84d2fCef62c5834FcBf38B700E5203679197;

    function run() external {
        vm.startBroadcast(deployerPrivateKey);

        // Get contract addresses
        address feeCollectorAddress = getFeeCollectorAddress();
        address merkleDistributorAddress = getMerkleDistributorAddress();

        console.log("FeeCollector address:", feeCollectorAddress);
        console.log("MerkleDistributor address:", merkleDistributorAddress);
        console.log("Distributor address to grant role:", DISTRIBUTOR_ADDRESS);

        // Cast to contract interfaces
        FeeCollector feeCollector = FeeCollector(feeCollectorAddress);
        MerkleDistributor merkleDistributor = MerkleDistributor(merkleDistributorAddress);

        // Step 1: Grant DISTRIBUTOR_ROLE to the specified address on FeeCollector
        console.log("Granting DISTRIBUTOR_ROLE to", DISTRIBUTOR_ADDRESS, "on FeeCollector...");
        feeCollector.grantRole(feeCollector.DISTRIBUTOR_ROLE(), DISTRIBUTOR_ADDRESS);
        console.log("DISTRIBUTOR_ROLE granted to", DISTRIBUTOR_ADDRESS, "on FeeCollector");

        // Step 2: Grant DISTRIBUTOR_ROLE to FeeCollector on MerkleDistributor
        console.log("Granting DISTRIBUTOR_ROLE to FeeCollector on MerkleDistributor...");
        merkleDistributor.grantRole(merkleDistributor.DISTRIBUTOR_ROLE(), feeCollectorAddress);
        console.log("DISTRIBUTOR_ROLE granted to FeeCollector on MerkleDistributor");

        // Verify the configuration
        console.log("Verifying configuration...");
        
        // Verify FeeCollector role is granted correctly
        bool feeCollectorHasRole = feeCollector.hasRole(feeCollector.DISTRIBUTOR_ROLE(), DISTRIBUTOR_ADDRESS);
        require(feeCollectorHasRole, "FeeCollector role not granted correctly");
        console.log("FeeCollector role verification passed");

        // Verify MerkleDistributor role is granted correctly
        bool merkleDistributorHasRole = merkleDistributor.hasRole(merkleDistributor.DISTRIBUTOR_ROLE(), feeCollectorAddress);
        require(merkleDistributorHasRole, "MerkleDistributor role not granted correctly");
        console.log("MerkleDistributor role verification passed");

        console.log("Configuration completed successfully!");
        console.log("FeeCollector DISTRIBUTOR_ROLE granted to:", DISTRIBUTOR_ADDRESS);
        console.log("MerkleDistributor DISTRIBUTOR_ROLE granted to:", feeCollectorAddress);

        vm.stopBroadcast();
    }

    /**
     * @dev Gets the MerkleDistributor address for the current network and environment
     */
    function getMerkleDistributorAddress() internal view returns (address) {
        return getContractAddress("MERKLE_DISTRIBUTOR");
    }
} 