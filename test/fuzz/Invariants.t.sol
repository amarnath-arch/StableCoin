// SPDX-License-Identifier:MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

// our Invariants are :
// The total supply of the DSC should be less than the total value of the collateral
// Getter view functions should never revert : evergreen invariants

contract Invariants is StdInvariant, Test {
    DeployDSC deployer;
    DSCEngine dscEngine;
    DecentralizedStableCoin dsc;
    HelperConfig helperConfig;

    address weth;
    address wbtc;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dscEngine, helperConfig) = deployer.run();
        (, , weth, wbtc, ) = helperConfig.activeNetworkConfig();
        // targetContract(address(dscEngine));
        Handler handler = new Handler(address(dscEngine), address(dsc));
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueTotalSupply() public view {
        // get value of all collateral in the protocol
        // compare it to the debt
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dscEngine));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dscEngine));
        uint256 wethValue = dscEngine.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = dscEngine.getUsdValue(wbtc, totalWbtcDeposited);
        assert(wethValue + wbtcValue >= totalSupply);
    }
}
