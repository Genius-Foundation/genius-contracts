// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {GeniusExecutor} from "../../src/GeniusExecutor.sol";
import {GeniusVault} from "../../src/GeniusVault.sol";
import {GeniusActions} from "../../src/GeniusActions.sol";

/**
 * @title DeployPolygonGeniusEcosystem
 * @dev A contract for deploying the GeniusExecutor contract.
        Deployment commands:
        `source .env` // Load environment variables
        POLYGON: forge script script/deployment/DeployPolygonGeniusEcosystem.s.sol:DeployPolygonGeniusEcosystem --rpc-url $POLYGON_RPC_URL --broadcast -vvvv --via-ir
 */
contract DeployGeniusEcosystemCore is Script {
    bytes32 constant ORCHESTRATOR_ROLE = keccak256("ORCHESTRATOR_ROLE");

    GeniusVault public geniusVault;
    GeniusExecutor public geniusExecutor;

    function _run(
        address _stableAddress,
        address _permit2Address,
        address _owner,
        address[] memory orchestrators,
        address[] memory routers
    ) internal {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        // geniusActions = new GeniusActions(admin);

        GeniusVault implementation = new GeniusVault();

        bytes memory data = abi.encodeWithSelector(
            GeniusVault.initialize.selector,
            _stableAddress,
            _owner
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);

        geniusVault = GeniusVault(address(proxy));

        geniusExecutor = new GeniusExecutor(
            _permit2Address,
            address(geniusVault),
            _owner,
           routers
        );

        // Initialize the contracts
        geniusVault.setExecutor(address(geniusExecutor));

        // Add orchestrators
        for (uint256 i = 0; i < orchestrators.length; i++) {
            geniusVault.grantRole(ORCHESTRATOR_ROLE, orchestrators[i]);
        }

        console.log("GeniusVault deployed at: ", address(geniusVault));
        console.log("GeniusExecutor deployed at: ", address(geniusExecutor));
    }
}
