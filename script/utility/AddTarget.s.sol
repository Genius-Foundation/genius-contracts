import {Script, console} from "forge-std/Script.sol";

import {GeniusGasTank} from "../../src/GeniusGasTank.sol";

// Arbitrum: forge script script/utility/AddRoAddTargetuter.s.sol --rpc-url $BASE_RPC_URL --broadcast --via-ir --private-key $DEPLOYER_PRIVATE_KEY
contract AddTarget is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        address target = vm.envAddress("TARGET");

        GeniusGasTank geniusGasTank = GeniusGasTank(vm.envAddress("GAS_TANK"));

        geniusGasTank.setAllowedTarget(
            target,
            true
        );
        console.log(
            "Target added to GeniusGasTank"
        );
    }
}
