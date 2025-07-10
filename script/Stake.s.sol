// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {GeniusVault} from "../../src/GeniusVault.sol";

/**
 * @title GeniusStake
 * @dev
        source .env; forge script script/Stake.s.sol --rpc-url $AVALANCHE_RPC_URL --broadcast -vvvv --via-ir
 */
contract DeployGasTank is Script {
    bytes32 constant ORCHESTRATOR_ROLE = keccak256("ORCHESTRATOR_ROLE");

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        // geniusActions = new GeniusActions(admin);

        GeniusVault vaultInstance = GeniusVault(
            payable(vm.envAddress("GENIUS_VAULT_ADDRESS"))
        );

        vaultInstance.deposit(
            100_000_000,
            0x5CC11Ef1DE86c5E00259a463Ac3F3AE1A0fA2909
        );
    }
}
