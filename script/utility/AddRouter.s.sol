import {Script, console} from "forge-std/Script.sol";

import { GeniusExecutor } from "../../src/GeniusExecutor.sol";

// Arbitrum: forge script script/utility/AddRouter.s.sol --rpc-url $ARBITRUM_RPC_URL --broadcast --via-ir --sender 0x5CC11Ef1DE86c5E00259a463Ac3F3AE1A0fA2909 --private-key $DEPLOYER_PRIVATE_KEY
contract AddRouter is Script {

    function run() external {

        console.log("Sender", msg.sender);

        bytes32 DEFAULT_ADMIN_ROLE = 0x00;

        GeniusExecutor geniusExecutor = GeniusExecutor(payable(0x7365CE0CbdBfB9D510FB06cE8155a3229F46811F));

        bool _hasRole = geniusExecutor.hasRole(DEFAULT_ADMIN_ROLE, msg.sender);
        console.log("Has role", _hasRole);

        geniusExecutor.setAllowedTarget(0xf332761c673b59B21fF6dfa8adA44d78c12dEF09, true);
        console.log("Router '0xf332761c673b59B21fF6dfa8adA44d78c12dEF09' added to GeniusExecutor");
    }

}