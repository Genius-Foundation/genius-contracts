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
        source .env; forge script script/NewRouterProxyCallGasTank.s.sol --rpc-url $BASE_RPC_URL --broadcast -vvvv --via-ir
 */
contract NewRouterProxyCallGasTank is Script {
    GeniusVault public geniusVault;
    GeniusRouter public geniusRouter;
    GeniusGasTank public geniusGasTank;
    GeniusProxyCall public geniusProxyCall;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        // geniusActions = new GeniusActions(admin);

        address owner = vm.envAddress("OWNER_ADDRESS");
        address permit2 = vm.envAddress("PERMIT2_ADDRESS");
        geniusVault = GeniusVault(
            payable(vm.envAddress("GENIUS_VAULT_ADDRESS"))
        );

        geniusProxyCall = new GeniusProxyCall(owner, new address[](0));

        geniusRouter = new GeniusRouter(
            permit2,
            address(geniusVault),
            address(geniusProxyCall)
        );

        geniusGasTank = new GeniusGasTank(
            owner,
            payable(owner),
            permit2,
            address(geniusProxyCall)
        );

        geniusProxyCall.grantRole(
            keccak256("CALLER_ROLE"),
            address(geniusVault)
        );
        geniusProxyCall.grantRole(
            keccak256("CALLER_ROLE"),
            address(geniusRouter)
        );
        geniusProxyCall.grantRole(
            keccak256("CALLER_ROLE"),
            address(geniusGasTank)
        );

        geniusVault.setProxyCall(address(geniusProxyCall));

        console.log("GeniusProxyCall deployed at: ", address(geniusProxyCall));
        console.log("GeniusRouter deployed at: ", address(geniusRouter));
        console.log("GeniusGasTank deployed at: ", address(geniusGasTank));
    }
}
