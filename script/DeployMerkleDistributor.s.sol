// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {MerkleDistributor} from "../src/distributor/MerkleDistributor.sol";

/**
 * @title DeployMerkleDistributor
 * @dev A contract for deploying the MerkleDistributor contract with UUPS proxy.
 *      Deployment commands:
 *      `source .env` // Load environment variables
 *      ETHEREUM: source .env; forge script script/DeployMerkleDistributor.s.sol:DeployMerkleDistributor --rpc-url $ETHEREUM_RPC_URL --broadcast -vvvv --via-ir
 *      POLYGON: source .env; forge script script/DeployMerkleDistributor.s.sol:DeployMerkleDistributor --rpc-url $POLYGON_RPC_URL --broadcast -vvvv --via-ir
 *      BASE: source .env; forge script script/DeployMerkleDistributor.s.sol:DeployMerkleDistributor --rpc-url $BASE_RPC_URL --broadcast -vvvv --via-ir
 */
contract DeployMerkleDistributor is Script {
    MerkleDistributor public merkleDistributor;
    ERC1967Proxy public proxy;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address admin = vm.envAddress("OWNER_ADDRESS");
        
        vm.startBroadcast(deployerPrivateKey);

        // Deploy the implementation contract
        merkleDistributor = new MerkleDistributor();
        console.log("MerkleDistributor implementation deployed at: ", address(merkleDistributor));

        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            MerkleDistributor.initialize.selector,
            admin
        );

        // Deploy the proxy contract
        proxy = new ERC1967Proxy(
            address(merkleDistributor),
            initData
        );
        console.log("MerkleDistributor proxy deployed at: ", address(proxy));

        // Cast the proxy to MerkleDistributor for verification
        MerkleDistributor merkleDistributorProxy = MerkleDistributor(address(proxy));
        
        // Verify the deployment by checking if admin has the DEFAULT_ADMIN_ROLE
        bytes32 defaultAdminRole = 0x00; // DEFAULT_ADMIN_ROLE is 0x00
        require(
            merkleDistributorProxy.hasRole(defaultAdminRole, admin),
            "MerkleDistributor: admin role not set correctly"
        );

        console.log("MerkleDistributor deployment completed successfully!");
        console.log("Use address(proxy) for interactions: ", address(proxy));

        vm.stopBroadcast();
    }
} 