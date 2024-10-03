// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DeployGeniusEcosystemCore} from "./DeployGeniusEcosystemCore.s.sol";

// COMMAND: forge script script/deployment/DeployArbitrumGeniusEcosystem.s.sol --rpc-url $ARBITRUM_RPC_URL --broadcast --via-ir
contract DeployArbitrumGeniusEcosystem is DeployGeniusEcosystemCore {
    address public constant stableAddress = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address public constant permit2Address = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address public constant owner = 0x5CC11Ef1DE86c5E00259a463Ac3F3AE1A0fA2909;

    function run() external {
        address[] memory orchestrators = new address[](5);
        orchestrators[0] = 0x17cC1e3AF40C88B235d9837990B8ad4D7C06F5cc;
        orchestrators[1] = 0x4102b4144e9EFb8Cb0D7dc4A3fD8E65E4A8b8fD0;
        orchestrators[2] = 0x90B29aF53D2bBb878cAe1952B773A307330393ef;
        orchestrators[3] = 0x7e5E0712c627746a918ae2015e5bfAB51c86dA26;
        orchestrators[4] = 0x5975fBa1186116168C479bb21Bb335f02D504CFB;

        address[] memory routers = new address[](3);
        routers[0] = 0xa669e7A0d4b3e4Fa48af2dE86BD4CD7126Be4e13; // Odos
        routers[1] = 0x6131B5fae19EA4f9D964eAc0408E4408b66337b5; // Kyberswap
        routers[2] = 0xf332761c673b59B21fF6dfa8adA44d78c12dEF09; // OKX

        _run(stableAddress, permit2Address, owner, orchestrators, routers);
    }
}