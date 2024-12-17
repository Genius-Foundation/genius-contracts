// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DeployGeniusEcosystemCore} from "./DeployGeniusEcosystemCore.s.sol";

// COMMAND: forge script script/deployment/DeployOptimismGeniusEcosystem.s.sol --rpc-url $OPTIMISM_RPC_URL --broadcast --via-ir
contract DeployOptimismGeniusEcosystem is DeployGeniusEcosystemCore {
    address public constant stableAddress =
        0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
    address public constant priceFeed =
        0x16a9FA2FDa030272Ce99B29CF780dFA30361E0f3;
    address public constant permit2Address =
        0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address public constant owner = 0x5CC11Ef1DE86c5E00259a463Ac3F3AE1A0fA2909;

    function run() external {
        address[] memory orchestrators = new address[](1);
        orchestrators[0] = 0x1b58dd4DE6B7B3066D614905f5c8Fea9C81a1439;

        address[] memory feeTokens = new address[](5);
        feeTokens[0] = stableAddress; // USDC
        feeTokens[1] = stableAddress; // USDC
        feeTokens[2] = stableAddress; // USDC
        feeTokens[3] = stableAddress; // USDC
        feeTokens[4] = stableAddress; // USDC

        uint256[] memory minFeeAmounts = new uint256[](5);
        minFeeAmounts[0] = 100000; // $0.1
        minFeeAmounts[1] = 1000000; // $1
        minFeeAmounts[2] = 100000; // $0.1
        minFeeAmounts[3] = 100000; // $0.1
        minFeeAmounts[4] = 100000; // $0.1

        uint256[] memory targetNetworks = new uint256[](5);
        targetNetworks[0] = 8453; // BASE
        targetNetworks[1] = 1; // ETHEREUM
        targetNetworks[2] = 42161; // ARBITRUM
        targetNetworks[3] = 43114; // AVALANCHE
        targetNetworks[4] = 1399811149; // SOLANA

        _run(
            permit2Address,
            stableAddress,
            priceFeed,
            owner,
            orchestrators,
            targetNetworks,
            feeTokens,
            minFeeAmounts
        );
    }
}
