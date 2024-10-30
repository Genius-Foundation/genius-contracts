// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DeployGeniusEcosystemCore} from "./DeployGeniusEcosystemCore.s.sol";

// COMMAND: forge script script/deployment/DeployOptimismGeniusEcosystem.s.sol --rpc-url $OPTIMISM_RPC_URL --broadcast --via-ir
contract DeployOptimismGeniusEcosystem is DeployGeniusEcosystemCore {
    address public constant stableAddress =
        0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
    address public constant permit2Address =
        0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address public constant owner = 0x5CC11Ef1DE86c5E00259a463Ac3F3AE1A0fA2909;

    function run() external {
        address[] memory orchestrators = new address[](5);
        orchestrators[0] = 0x17cC1e3AF40C88B235d9837990B8ad4D7C06F5cc;
        orchestrators[1] = 0x4102b4144e9EFb8Cb0D7dc4A3fD8E65E4A8b8fD0;
        orchestrators[2] = 0x90B29aF53D2bBb878cAe1952B773A307330393ef;
        orchestrators[3] = 0x7e5E0712c627746a918ae2015e5bfAB51c86dA26;
        orchestrators[4] = 0x5975fBa1186116168C479bb21Bb335f02D504CFB;

        address[] memory feeTokens = new address[](1);
        feeTokens[0] = 0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA; // USDC

        uint256[] memory minFeeAmounts = new uint256[](1);
        minFeeAmounts[0] = 100000; // $0.1

        uint256[] memory targetNetworks = new uint256[](1);
        targetNetworks[0] = 8453; // BASE

        _run(
            permit2Address,
            stableAddress,
            owner,
            orchestrators,
            targetNetworks,
            feeTokens,
            minFeeAmounts
        );
    }
}
