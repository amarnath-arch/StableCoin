//SPDX-License-Identifier:MIT
pragma solidity ^0.8.11;

import {Script} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDSC is Script {
    address[] public tokenCollateralAddresses;
    address[] public priceFeedAddresses;

    function run()
        external
        returns (DecentralizedStableCoin, DSCEngine, HelperConfig)
    {
        HelperConfig helperConfig = new HelperConfig();
        (
            address wethUsdPriceFeedAddress,
            address wbtcUsdPriceFeedAddress,
            address weth,
            address wbtc,
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig();

        // address[] memory tokenCollateralAddresses;
        tokenCollateralAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeedAddress, wbtcUsdPriceFeedAddress];

        vm.startBroadcast(deployerKey);
        DecentralizedStableCoin Dsc = new DecentralizedStableCoin();
        DSCEngine DscEngine = new DSCEngine(
            tokenCollateralAddresses,
            priceFeedAddresses,
            address(Dsc)
        );

        Dsc.transferOwnership(address(DscEngine));
        vm.stopBroadcast();

        return (Dsc, DscEngine, helperConfig);
    }
}
