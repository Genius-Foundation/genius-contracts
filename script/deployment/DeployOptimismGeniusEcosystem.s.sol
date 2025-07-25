// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DeployGeniusEcosystemCore} from "./DeployGeniusEcosystemCore.s.sol";

// COMMAND: forge script script/deployment/DeployOptimismGeniusEcosystem.s.sol --rpc-url $OPTIMISM_RPC_URL --broadcast --via-ir
contract DeployOptimismGeniusEcosystem is DeployGeniusEcosystemCore {
    address public constant stableAddress =
        0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85;
    address public constant priceFeed =
        0x16a9FA2FDa030272Ce99B29CF780dFA30361E0f3;
    uint256 public constant priceFeedHeartBeat = 86400;
    address public constant permit2Address =
        0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address public constant owner = 0xB3dff85e6D173dB754Ef2E617713dCab2a37E7c3;

    function run() external {
        uint256[] memory allChainIds = new uint256[](9);
        allChainIds[0] = 56; // BSC
        allChainIds[1] = 8453; // BASE
        allChainIds[2] = 42161; // ARBITRUM
        allChainIds[3] = 10; // OPTIMISM
        allChainIds[4] = 43114; // AVALANCHE
        allChainIds[5] = 1399811149; // SOLANA
        allChainIds[6] = 137; // POLYGON
        allChainIds[7] = 146; // SONIC
        allChainIds[8] = 1; // ETHEREUM

        uint256[] memory minFees = new uint256[](9);
        minFees[0] = 100_000; // $0.1 BSC (6 decimals)
        minFees[1] = 100_000; // $0.1 BASE
        minFees[2] = 100_000; // $0.1 ARBITRUM
        minFees[3] = 100_000; // $0.1 OPTIMISM
        minFees[4] = 100_000; // $0.1 AVALANCHE
        minFees[5] = 100_000; // $0.1 SOLANA
        minFees[6] = 100_000; // $0.1 POLYGON
        minFees[7] = 100_000; // $0.1 SONIC
        minFees[8] = 1_000_000; // $1 ETHEREUM

        uint256[] memory thresholdAmounts = new uint256[](4);
        thresholdAmounts[0] = 0; // Smallest orders
        thresholdAmounts[1] = 100_000_000; // Medium orders (above 100 dollars)
        thresholdAmounts[2] = 1_000_000_000; // Large orders (above 1000 dollars)
        thresholdAmounts[3] = 10_000_000_000; // Large orders (above 10k dollars)

        uint256[] memory bpsFees = new uint256[](4);
        bpsFees[0] = 50; // 0.5% for smallest orders
        bpsFees[1] = 35; // 0.35% for medium orders
        bpsFees[2] = 25; // 0.25% for large orders
        bpsFees[3] = 15; // 0.15% for large orders (above 10k dollars)

        uint256 insuranceFee = 2; // 0.02% for insurance fee
        uint256 maxOrderSize = 10_000_000_000; // 10,000usd

        _run(
            permit2Address,
            stableAddress,
            priceFeed,
            priceFeedHeartBeat,
            owner,
            allChainIds,
            minFees,
            thresholdAmounts,
            bpsFees,
            insuranceFee,
            maxOrderSize
        );
    }
}
