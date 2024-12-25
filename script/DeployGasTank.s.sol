// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {GeniusGasTank} from "../../src/GeniusGasTank.sol";
import {GeniusProxyCall} from "../../src/GeniusProxyCall.sol";

/**
 * @title DeployPolygonGeniusEcosystem
 * @dev A contract for deploying the GeniusExecutor contract.
        Deployment commands:
        `source .env` // Load environment variables
        source .env; forge script script/DeployGasTank.s.sol --rpc-url $BASE_RPC_URL --broadcast -vvvv --via-ir
 */
contract DeployGasTank is Script {
    bytes32 constant ORCHESTRATOR_ROLE = keccak256("ORCHESTRATOR_ROLE");

    GeniusGasTank public geniusGasTank;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        // geniusActions = new GeniusActions(admin);

        address owner = vm.envAddress("OWNER_ADDRESS");
        address permit2 = vm.envAddress("PERMIT2_ADDRESS");
        GeniusProxyCall proxyCall = GeniusProxyCall(
            payable(vm.envAddress("PROXY_CALL_ADDRESS"))
        );

        geniusGasTank = new GeniusGasTank(
            owner,
            payable(owner),
            permit2,
            address(proxyCall)
        );

        proxyCall.grantRole(keccak256("CALLER_ROLE"), address(geniusGasTank));

        console.log("GeniusGasTank deployed at: ", address(geniusGasTank));
    }
}
