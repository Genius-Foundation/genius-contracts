// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {GeniusExecutor} from "../../src/GeniusExecutor.sol";
import {GeniusPool} from "../../src/GeniusPool.sol";
import {GeniusVault} from "../../src/GeniusVault.sol";
import {GeniusActions} from "../../src/GeniusActions.sol";

contract UpgradeAvalanche is Script {

    address public constant stableAddress = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    address public constant permit2Address = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    address public constant owner = 0x5CC11Ef1DE86c5E00259a463Ac3F3AE1A0fA2909;
    address public constant admin = 0x6192A053B05942e9D7EB98e3b2146283aD559e62;

    address public constant legacyPool = 0x69017CAF9655c8d54cFBF6b030E3e2f02baB7268;
    address public constant legacyVault = 0x7e204f2d874AFa344fDfA428eC9d77C07c556bAC;

    GeniusPool public geniusPool;
    GeniusVault public geniusVault;
    GeniusExecutor public geniusExecutor;
    GeniusActions public geniusActions;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        uint256 orchestratorPrivateKey = vm.envUint("ORCHESTRATOR_1_PRIVATE_KEY");

        // Remove funds from the legacy pool
        GeniusPool _geniusPool = GeniusPool(legacyPool);
        GeniusVault _geniusVault = GeniusVault(legacyVault);

        // uint256 _amountToUnstake = _geniusVault.balanceOf(0x2Cd60849380319b59e180BC2137352C6dF838A33);
        // uint256 _poolBalance = IERC20(stableAddress).balanceOf(legacyPool);

        // // Unstake the funds
        // vm.startBroadcast(0x4d3f78f5c7b3b5458ba5901e909884163e1d7d1b223f40961fb4a5930b8e6d6e);
        // _geniusVault.withdraw(
        //     _amountToUnstake,
        //     0x17cC1e3AF40C88B235d9837990B8ad4D7C06F5cc,
        //     0x2Cd60849380319b59e180BC2137352C6dF838A33
        // );
        // vm.stopBroadcast();

        vm.startBroadcast(orchestratorPrivateKey);
        uint256 _amount = IERC20(stableAddress).balanceOf(address(_geniusPool));

        // Remove assets from the pool
        _geniusPool.removeLiquiditySwap(
            owner,
            _amount
        );
        vm.stopBroadcast();

        vm.startBroadcast(deployerPrivateKey);
        (
          address _newgeniusPoolAddress,
          ,
        ) = _deploy();
        vm.stopBroadcast();


        vm.startBroadcast(orchestratorPrivateKey);
        // Add funds to the new pool
        GeniusPool _newGeniusPool = GeniusPool(_newgeniusPoolAddress);

        uint256 _amountToDeposit = IERC20(stableAddress).balanceOf(0x17cC1e3AF40C88B235d9837990B8ad4D7C06F5cc);

        // Approve the pool
        IERC20(stableAddress).approve(address(_newGeniusPool), _amountToDeposit);

        _newGeniusPool.addLiquiditySwap(
            owner,
            stableAddress,
            _amountToDeposit
        );

        console.log("Funds moved from legacy pool to new pool");
    }  

    function _deploy() internal returns (address, address, address) {
        geniusVault = new GeniusVault(stableAddress, owner);

        geniusPool = new GeniusPool(
            stableAddress, 
            owner
        );

        geniusExecutor = new GeniusExecutor(
            permit2Address,
            address(geniusPool),
            address(geniusVault)
        );

        // Initialize the contracts
        geniusPool.initialize(address(geniusVault));
        geniusVault.initialize(address(geniusPool));

        // Add orchestrators
        geniusPool.addOrchestrator(0x17cC1e3AF40C88B235d9837990B8ad4D7C06F5cc);
        geniusPool.addOrchestrator(0x4102b4144e9EFb8Cb0D7dc4A3fD8E65E4A8b8fD0);
        geniusPool.addOrchestrator(0x90B29aF53D2bBb878cAe1952B773A307330393ef);
        geniusPool.addOrchestrator(0x7e5E0712c627746a918ae2015e5bfAB51c86dA26);
        geniusPool.addOrchestrator(0x5975fBa1186116168C479bb21Bb335f02D504CFB);


        console.log("GeniusPool deployed at: ", address(geniusPool));
        console.log("GeniusVault deployed at: ", address(geniusVault));
        console.log("GeniusExecutor deployed at: ", address(geniusExecutor));

        return (address(geniusPool), address(geniusVault), address(geniusExecutor));
    }  

}