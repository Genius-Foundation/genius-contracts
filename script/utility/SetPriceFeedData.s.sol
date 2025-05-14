// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";

import {GeniusVault} from "../../src/GeniusVault.sol";

contract UpdatePriceFeedSettings is Script {
    GeniusVault public geniusVault;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Replace with your deployed vault address
        geniusVault = GeniusVault(0xA3372621d29e65fb1853BbeF2D78f63db135A2c2);
        
        // Price feed address - replace with the appropriate Chainlink price feed for your stablecoin
        address priceFeed = 0x0A6513e40db6EB1b165753AD52E80663aeA50545; // Example address, replace with actual
        
        // Heartbeat threshold in seconds
        // Typical heartbeat for stablecoins: 86400 (24 hours)
        uint256 heartbeat = 86400; 
        
        // Price bounds for stablecoin (8 decimals like Chainlink)
        // For a stablecoin like USDC, typical range might be 0.95-1.05 USD
        // Represented with 8 decimals: 95000000 to 105000000
        uint256 lowerBound = 95000000;  // $0.95 with 8 decimals
        uint256 upperBound = 105000000; // $1.05 with 8 decimals
        
        // Update price feed address if needed
        address currentPriceFeed = address(geniusVault.stablecoinPriceFeed());
        if (currentPriceFeed != priceFeed) {
            console.log("Updating price feed from", currentPriceFeed, "to", priceFeed);
            geniusVault.setPriceFeed(priceFeed);
        }
        
        // Update heartbeat if needed
        uint256 currentHeartbeat = geniusVault.priceFeedHeartbeat();
        if (currentHeartbeat != heartbeat) {
            console.log("Updating heartbeat from", currentHeartbeat, "to", heartbeat);
            geniusVault.setPriceFeedHeartbeat(heartbeat);
        }
        
        // Update price bounds if needed
        uint256 currentLowerBound = geniusVault.stablePriceLowerBound();
        uint256 currentUpperBound = geniusVault.stablePriceUpperBound();
        
        if (currentLowerBound != lowerBound || currentUpperBound != upperBound) {
            geniusVault.setStablePriceBounds(lowerBound, upperBound);
        }
        
        vm.stopBroadcast();
    }
}