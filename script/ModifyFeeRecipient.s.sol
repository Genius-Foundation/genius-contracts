// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {GeniusGasTank} from "../src/GeniusGasTank.sol";

/**
 * @title ModifyFeeRecipient
 * @dev A script for updating the fee recipient on GeniusGasTank contracts across multiple chains.
 *      This script will call setFeeRecipient with the GASTANK_FEE_COLLECTOR_ADDRESS from .env.
 *      
 *      Prerequisites:
 *      - Set ADMIN_PRIVATE_KEY in .env (account with DEFAULT_ADMIN_ROLE on GeniusGasTank)
 *      - Set GASTANK_FEE_COLLECTOR_ADDRESS in .env (new fee recipient address)
 *      - Set GASTANK_ADDRESS in .env (GeniusGasTank contract address for the target chain)
 *      
 *      Deployment commands:
 *      `source .env` // Load environment variables
 *      
 *      ETHEREUM: source .env; forge script script/ModifyFeeRecipient.s.sol:ModifyFeeRecipient --rpc-url $ETHEREUM_RPC_URL --broadcast -vvvv
 *      POLYGON: source .env; forge script script/ModifyFeeRecipient.s.sol:ModifyFeeRecipient --rpc-url $POLYGON_RPC_URL --broadcast -vvvv
 *      BSC: source .env; forge script script/ModifyFeeRecipient.s.sol:ModifyFeeRecipient --rpc-url $BSC_RPC_URL --broadcast -vvvv
 *      ARBITRUM: source .env; forge script script/ModifyFeeRecipient.s.sol:ModifyFeeRecipient --rpc-url $ARBITRUM_RPC_URL --broadcast -vvvv
 *      OPTIMISM: source .env; forge script script/ModifyFeeRecipient.s.sol:ModifyFeeRecipient --rpc-url $OPTIMISM_RPC_URL --broadcast -vvvv
 *      BASE: source .env; forge script script/ModifyFeeRecipient.s.sol:ModifyFeeRecipient --rpc-url $BASE_RPC_URL --broadcast -vvvv
 *      AVALANCHE: source .env; forge script script/ModifyFeeRecipient.s.sol:ModifyFeeRecipient --rpc-url $AVALANCHE_RPC_URL --broadcast -vvvv
 *      HYPER: source .env; forge script script/ModifyFeeRecipient.s.sol:ModifyFeeRecipient --rpc-url $HYPER_RPC_URL --broadcast -vvvv
 */
contract ModifyFeeRecipient is Script {
    // Chain IDs
    uint256 constant ETHEREUM = 1;
    uint256 constant OPTIMISM = 10;
    uint256 constant BSC = 56;
    uint256 constant POLYGON = 137;
    uint256 constant SONIC = 146;
    uint256 constant ARBITRUM = 42161;
    uint256 constant AVAX = 43114;
    uint256 constant BASE = 8453;
    uint256 constant HYPER = 999; // HyperEVM chain ID

    function run() external {
        // Load environment variables
        uint256 adminPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address payable newFeeRecipient = payable(0xf70853810B8fC6869068Dc8F7f94c439c9a2cdCa);
        address gasTankAddress = getGasTankAddress(block.chainid);

        // Get chain info for logging
        uint256 chainId = block.chainid;
        string memory networkName = getNetworkName(chainId);

        console.log("===========================================");
        console.log("Modifying Fee Recipient on GeniusGasTank");
        console.log("===========================================");
        console.log("Network:", networkName);
        console.log("Chain ID:", chainId);
        console.log("GeniusGasTank address:", gasTankAddress);
        console.log("New fee recipient:", newFeeRecipient);

        // Get the GeniusGasTank contract
        GeniusGasTank gasTank = GeniusGasTank(gasTankAddress);

        // Start broadcast with admin private key
        vm.startBroadcast(adminPrivateKey);

        // Call setFeeRecipient
        console.log("Calling setFeeRecipient...");
        gasTank.setFeeRecipient(newFeeRecipient);

        vm.stopBroadcast();

        console.log("===========================================");
        console.log("Fee recipient updated successfully!");
        console.log("===========================================");
    }

    /**
     * @dev Maps chain ID to network name for logging
     */
    function getNetworkName(uint256 _chainId) internal pure returns (string memory) {
        if (_chainId == AVAX) return "AVALANCHE";
        if (_chainId == BASE) return "BASE";
        if (_chainId == ARBITRUM) return "ARBITRUM";
        if (_chainId == OPTIMISM) return "OPTIMISM";
        if (_chainId == SONIC) return "SONIC";
        if (_chainId == POLYGON) return "POLYGON";
        if (_chainId == BSC) return "BSC";
        if (_chainId == ETHEREUM) return "ETHEREUM";
        if (_chainId == HYPER) return "HYPER";
        return "UNKNOWN";
    }

    /**
     * @dev Maps chain ID to GeniusGasTank deployment address
     */
    function getGasTankAddress(uint256 _chainId) internal pure returns (address) {
        if (_chainId == ETHEREUM) return 0x0C7877388B897632F7D843C634D761Fd59b2151D;
        if (_chainId == AVAX) return 0xF93977284b4264B2Dfc74c0FC449770b1d4fD543;
        if (_chainId == ARBITRUM) return 0xfDb035E0cff87E0F53DCC6DADFC28EB13536E70E;
        if (_chainId == BASE) return 0x68a94011F255A340203b36eC505262f9cff29870;
        if (_chainId == OPTIMISM) return 0x50f29A0664D587DA898207FE0f631dD2DBd6cA3C;
        if (_chainId == POLYGON) return 0x8B29b4DcEC5E4d7da7D8C4e8206da746b7c3894d;
        if (_chainId == BSC) return 0x2810A20B34311a1F69F74264AB48aC29240003FD;
        if (_chainId == SONIC) return 0xB8C75a235257123bBA47D8F4f1c77eC8740Ba423;
        if (_chainId == HYPER) return 0x11e2FeBEe17e7F920D596Ef1ABDC928E4872B5E3;
        revert("GasTank not deployed on this chain");
    }
}
