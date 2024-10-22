// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {GeniusProxyCall} from "../../src/GeniusProxyCall.sol";
import {GeniusVault} from "../../src/GeniusVault.sol";
import {GeniusActions} from "../../src/GeniusActions.sol";
import {GeniusRouter} from "../../src/GeniusRouter.sol";
import {GeniusGasTank} from "../../src/GeniusGasTank.sol";

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
    GeniusRouter public geniusRouter;
    GeniusGasTank public geniusGasTank;
    GeniusProxyCall public geniusMulticall;

    function _run(
        address _permit2Address,
        address _stableAddress,
        address _owner,
        address[] memory orchestrators
    ) internal {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        // geniusActions = new GeniusActions(admin);

        geniusMulticall = new GeniusProxyCall(_owner, new address[](0));

        GeniusVault implementation = new GeniusVault();

        bytes memory data = abi.encodeWithSelector(
            GeniusVault.initialize.selector,
            _stableAddress,
            _owner,
            address(geniusMulticall),
            7_500,
            30,
            300
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);

        geniusVault = GeniusVault(address(proxy));

        geniusRouter = new GeniusRouter(
            _permit2Address,
            address(geniusVault),
            address(geniusMulticall)
        );

        geniusGasTank = new GeniusGasTank(
            _owner,
            payable(_owner),
            _permit2Address,
            address(geniusMulticall)
        );

        // Add orchestrators
        for (uint256 i = 0; i < orchestrators.length; i++) {
            geniusVault.grantRole(ORCHESTRATOR_ROLE, orchestrators[i]);
        }

        console.log("GeniusProxyCall deployed at: ", address(geniusMulticall));
        console.log("GeniusVault deployed at: ", address(geniusVault));
        console.log("GeniusRouter deployed at: ", address(geniusRouter));
        console.log("GeniusGasTank deployed at: ", address(geniusGasTank));
    }
}
