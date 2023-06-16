//SPDX-License-Identifier:MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract Handler is Test {
    DSCEngine dscEngine;
    DecentralizedStableCoin dsc;

    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 MAX_DEPOSIT_AMOUNT = type(uint96).max;

    address[] public usersWithCollateralDeposited;

    constructor(address _dscEngine, address _dsc) {
        dscEngine = DSCEngine(_dscEngine);
        dsc = DecentralizedStableCoin(_dsc);

        address[] memory collateralTokens = dscEngine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
    }

    function depositCollateral(
        uint256 collateralSeed,
        uint256 collateralAmount
    ) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        collateralAmount = bound(collateralAmount, 1, MAX_DEPOSIT_AMOUNT);
        collateralAmount = 10 ether;

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, collateralAmount);
        collateral.approve(address(dscEngine), collateralAmount);
        dscEngine.depositCollateral(address(collateral), collateralAmount);
        usersWithCollateralDeposited.push(msg.sender);
        vm.stopPrank();
    }

    function redeemCollateral(
        uint256 collateralSeed,
        uint256 collateralAmount
    ) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = dscEngine.getCollateralBalance(
            address(collateral),
            msg.sender
        );
        collateralAmount = bound(collateralAmount, 0, maxCollateralToRedeem);
        if (collateralAmount == 0) return;
        vm.prank(msg.sender);
        dscEngine.redeemCollateral(address(collateral), collateralAmount);
    }

    function mintDsc(uint256 amount, uint256 addressSeed) public {
        if (usersWithCollateralDeposited.length == 0) return;
        address sender = usersWithCollateralDeposited[
            addressSeed % usersWithCollateralDeposited.length
        ];
        (uint256 totalDscMinted, uint256 collateralValueInusd) = dscEngine
            .getAccountInformation(sender);

        int256 maxDscToMint = (int256(collateralValueInusd) / 2) -
            int256(totalDscMinted);
        if (maxDscToMint < 0) return;
        amount = bound(amount, 0, uint256(maxDscToMint));
        if (amount == 0) return;
        vm.startPrank(sender);
        dscEngine.mintDsc(amount);
        vm.stopPrank();
    }

    // Helper Functions
    function _getCollateralFromSeed(
        uint256 collateralSeed
    ) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) return weth;
        return wbtc;
    }
}
