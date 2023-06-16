//SPDX-License-Identifier:MIT

pragma solidity ^0.8.11;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/Mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address wethUsdPriceFeedAddress;
        address wbtcUsdPriceFeedAddress;
        address weth;
        address wbtc;
        uint256 deployerKey;
    }

    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000e8;
    int256 public constant BTCUSD_PRICE = 1000e8;
    uint256 private constant DEFAULT_ANVIL_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory) {
        return
            NetworkConfig({
                wethUsdPriceFeedAddress: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
                wbtcUsdPriceFeedAddress: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
                weth: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
                wbtc: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
                deployerKey: vm.envUint("PRIVATE_KEY")
            });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        // check to see if we there is already an active Network Config
        if (activeNetworkConfig.wethUsdPriceFeedAddress != address(0))
            return activeNetworkConfig;

        vm.startBroadcast();
        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(
            DECIMALS,
            ETH_USD_PRICE
        );
        ERC20Mock wethMock = new ERC20Mock();

        MockV3Aggregator btcUsdPriceFeed = new MockV3Aggregator(
            DECIMALS,
            BTCUSD_PRICE
        );
        ERC20Mock wbtcMock = new ERC20Mock();

        vm.stopBroadcast();

        return
            NetworkConfig({
                wethUsdPriceFeedAddress: address(ethUsdPriceFeed),
                wbtcUsdPriceFeedAddress: address(btcUsdPriceFeed),
                weth: address(wethMock),
                wbtc: address(wbtcMock),
                deployerKey: DEFAULT_ANVIL_KEY
            });
    }
}
