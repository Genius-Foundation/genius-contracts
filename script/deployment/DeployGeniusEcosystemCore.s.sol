// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {GeniusProxyCall} from "../../src/GeniusProxyCall.sol";
import {GeniusVault} from "../../src/GeniusVault.sol";
import {GeniusRouter} from "../../src/GeniusRouter.sol";
import {GeniusGasTank} from "../../src/GeniusGasTank.sol";
import {FeeCollector} from "../../src/fees/FeeCollector.sol";

/**
 * @title DeployPolygonGeniusEcosystem
 * @dev A contract for deploying the GeniusExecutor contract.
        Deployment commands:
        `source .env` // Load environment variables
        POLYGON: forge script script/deployment/DeployPolygonGeniusEcosystem.s.sol:DeployPolygonGeniusEcosystem --rpc-url $POLYGON_RPC_URL --broadcast -vvvv --via-ir
 */
contract DeployGeniusEcosystemCore is Script {
    bytes32 constant ORCHESTRATOR_ROLE = keccak256("ORCHESTRATOR_ROLE");

    GeniusVault public geniusVault;
    GeniusRouter public geniusRouter;
    GeniusGasTank public geniusGasTank;
    GeniusProxyCall public geniusProxyCall;

    function _run(
        address _permit2Address,
        address _stableAddress,
        address _priceFeed,
        uint256 _priceFeedHeartbeat,
        address _owner,
        address[] memory orchestrators,
        uint256[] memory targetNetworks,
        address[] memory feeTokens,
        uint256[] memory minFeeAmounts
    ) internal {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        // geniusActions = new GeniusActions(admin);

        geniusProxyCall = new GeniusProxyCall(_owner, new address[](0));

        GeniusVault implementation = new GeniusVault();

        bytes memory data = abi.encodeWithSelector(
            GeniusVault.initialize.selector,
            _stableAddress,
            _owner,
            address(geniusProxyCall),
            7_500,
            _priceFeed,
            _priceFeedHeartbeat,
            99_000_000,
            101_000_000,
            100_000_000 // 100usd
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);

        geniusVault = GeniusVault(address(proxy));

        // Deploy FeeCollector implementation
        FeeCollector feeCollectorImpl = new FeeCollector();
        console.log(
            "FeeCollector implementation deployed at:",
            address(feeCollectorImpl)
        );

        address protocolFeeReceiver = _owner;
        address lpFeeReceiver = _owner;
        address operatorFeeReceiver = _owner;

        // Prepare initialization data
        bytes memory feeCollectorInitData = abi.encodeWithSelector(
            FeeCollector.initialize.selector,
            _owner, // admin address
            _stableAddress, // stablecoin address
            1000, // 10% protocol fee
            protocolFeeReceiver,
            lpFeeReceiver,
            operatorFeeReceiver
        );

        // Deploy proxy
        ERC1967Proxy feeCollectorProxy = new ERC1967Proxy(
            address(feeCollectorImpl),
            feeCollectorInitData
        );
        console.log(
            "FeeCollector proxy deployed at:",
            address(feeCollectorProxy)
        );

        geniusRouter = new GeniusRouter(
            _permit2Address,
            address(geniusVault),
            address(geniusProxyCall),
            address(feeCollectorProxy) // Assuming feeCollector is set up elsewhere
        );

        geniusGasTank = new GeniusGasTank(
            _owner,
            payable(_owner),
            _permit2Address,
            address(geniusProxyCall)
        );

        // Add orchestrators
        for (uint256 i = 0; i < orchestrators.length; i++) {
            geniusVault.grantRole(ORCHESTRATOR_ROLE, orchestrators[i]);
        }

        // Set up fee tiers based on order size - moved to fee collector
        // This is handled by the FeeCollector now, not the vault
        // uint256[] memory thresholdAmounts = new uint256[](3);
        // thresholdAmounts[0] = 0;       // First tier starts at 0 (smallest orders)
        // thresholdAmounts[1] = 1000000; // 1000 USD (with 6 decimals)
        // thresholdAmounts[2] = 10000000; // 10000 USD (with 6 decimals)

        // uint256[] memory bpsFees = new uint256[](3);
        // bpsFees[0] = 30; // 0.3% for smallest orders
        // bpsFees[1] = 20; // 0.2% for medium orders
        // bpsFees[2] = 10; // 0.1% for large orders

        // FeeCollector deployment and setup should be handled separately

        geniusProxyCall.grantRole(
            keccak256("CALLER_ROLE"),
            address(geniusVault)
        );
        geniusProxyCall.grantRole(
            keccak256("CALLER_ROLE"),
            address(geniusRouter)
        );
        geniusProxyCall.grantRole(
            keccak256("CALLER_ROLE"),
            address(geniusGasTank)
        );

        console.log("GeniusProxyCall deployed at: ", address(geniusProxyCall));
        console.log("GeniusVault deployed at: ", address(geniusVault));
        console.log("GeniusRouter deployed at: ", address(geniusRouter));
        console.log("GeniusGasTank deployed at: ", address(geniusGasTank));
    }
}
