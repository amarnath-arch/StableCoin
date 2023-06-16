//SPDX-License-Identifier:MIT
pragma solidity ^0.8.11;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../Mocks/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    DSCEngine public dscEngine;
    DecentralizedStableCoin public dsc;
    HelperConfig public helperConfig;

    address public wethUsdPriceFeed;
    address public wbtcUsdPriceFeed;
    address public weth;
    address public wbtc;
    uint256 public deployerKey;

    uint256 amountCollateral = 10 ether;

    address public user = makeAddr("user");
    uint256 public constant STARTING_USER_BALANCE = 100 ether;

    function setUp() external {
        DeployDSC deployer = new DeployDSC();
        (dsc, dscEngine, helperConfig) = deployer.run();

        (
            wethUsdPriceFeed,
            wbtcUsdPriceFeed,
            weth,
            wbtc,
            deployerKey
        ) = helperConfig.activeNetworkConfig();

        ERC20Mock(weth).mint(user, STARTING_USER_BALANCE);
        ERC20Mock(wbtc).mint(user, STARTING_USER_BALANCE);
        ERC20Mock(weth).mint(user2, STARTING_USER_BALANCE);
        ERC20Mock(wbtc).mint(user2, STARTING_USER_BALANCE);
    }

    ///////////////////////
    // Constructor Tests //
    ///////////////////////

    address[] private tokenCollateralAddresses;
    address[] private priceFeedAddresses;

    function testcollateralAddressesAndPriceFeedAddressesAreOfSameLength()
        external
    {
        tokenCollateralAddresses.push(weth);
        priceFeedAddresses.push(wethUsdPriceFeed);
        priceFeedAddresses.push(wbtcUsdPriceFeed);
        vm.expectRevert(
            DSCEngine
                .DSCEngine__TokenCollateralAddressesAndPriceFeedAddressesMustBeOfSameLength
                .selector
        );
        new DSCEngine(
            tokenCollateralAddresses,
            priceFeedAddresses,
            address(dsc)
        );
    }

    //////////////////
    // Price Tests //
    //////////////////

    function testGetTokenAmountFromUsd() external {
        uint256 usdAmount = 10 ether;
        // $2000/ eth
        uint256 expectedTokenAmount = 0.005 ether;
        uint256 tokenAmount = dscEngine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedTokenAmount, tokenAmount);
    }

    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        // 15e18 ETH * $2000/ETH = $30,000e18
        uint256 expectedUsd = 30000e18;
        uint256 usdValue = dscEngine.getUsdValue(weth, ethAmount);
        assertEq(usdValue, expectedUsd);
    }

    ///////////////////////////////////////
    // depositCollateral Tests ////////////
    ///////////////////////////////////////

    modifier collateralDeposit() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateral(weth, amountCollateral);
        vm.stopPrank();
        _;
    }

    function testOtherTokensCanBeDepositedOrNot() external {
        ERC20Mock mockERC20 = new ERC20Mock();
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        dscEngine.depositCollateral(address(mockERC20), amountCollateral);
        vm.stopPrank();
    }

    function testRevertsIfCollateralZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), amountCollateral);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeGreaterThanZero.selector);
        dscEngine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testCanDepositTokensAndGetAccountInformation()
        external
        collateralDeposit
    {
        (uint256 totalDscMinted, uint256 collateralValueinUsd) = dscEngine
            .getAccountInformation(user);
        uint256 expectedDscMinted = 0;
        uint256 expectedCollateralValueInUsd = 20000e18; // 2000 * 10 * 1e18
        assertEq(expectedDscMinted, totalDscMinted);
        assertEq(expectedCollateralValueInUsd, collateralValueinUsd);
    }

    ///////////////////////////////////////
    // mintDsc Tests ////////////
    ///////////////////////////////////////

    function testMorethanZeroDscToMint() external {
        vm.prank(user);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeGreaterThanZero.selector);
        dscEngine.mintDsc(0);
    }

    function testRevertsIfHealthFactorisBroken1() external {
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__BreaksHealthFactor.selector,
                0
            )
        );
        dscEngine.mintDsc(10e18);
    }

    function testRevertsIfHealthFactorIsBroken2() external collateralDeposit {
        (, int price, , , ) = MockV3Aggregator(wethUsdPriceFeed)
            .latestRoundData();
        uint256 amountToMint = (amountCollateral *
            (uint256(price) * dscEngine.getAdditionalFeedPrecision())) /
            dscEngine.getPrecision();

        uint256 expectedHealthFactor = dscEngine.calculateHealthFactor(
            amountToMint,
            dscEngine.getUsdValue(weth, amountCollateral)
        );

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__BreaksHealthFactor.selector,
                expectedHealthFactor
            )
        );
        dscEngine.mintDsc(amountToMint);
    }

    function testSuccesfullyMintsTheDsc() external collateralDeposit {
        (, int price, , , ) = MockV3Aggregator(wethUsdPriceFeed)
            .latestRoundData();
        uint256 amountToMint = ((amountCollateral *
            (uint256(price) * dscEngine.getAdditionalFeedPrecision())) /
            dscEngine.getPrecision()) / 2;

        vm.prank(user);
        dscEngine.mintDsc(amountToMint);
        (uint256 totalDscMinted, ) = dscEngine.getAccountInformation(user);
        assertEq(totalDscMinted, amountToMint);
    }

    ///////////////////////////////////////////////////
    // depositCollateral and MintDSC Tests ////////////
    ///////////////////////////////////////////////////

    function testDepositsTheCollateralAndMintsDsc() external {
        (, int price, , , ) = MockV3Aggregator(wethUsdPriceFeed)
            .latestRoundData();
        uint256 amountToMint = ((amountCollateral *
            (uint256(price) * dscEngine.getAdditionalFeedPrecision())) /
            dscEngine.getPrecision()) / 2;

        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateralAndMintDsc(
            weth,
            amountCollateral,
            amountToMint
        );
        vm.stopPrank();

        (uint256 totalDscMinted, uint256 collateralValueinUsd) = dscEngine
            .getAccountInformation(user);
        uint256 expectedDscMinted = amountToMint;
        uint256 expectedTokenAmount = dscEngine.getTokenAmountFromUsd(
            weth,
            collateralValueinUsd
        );
        assertEq(expectedDscMinted, totalDscMinted);
        assertEq(expectedTokenAmount, amountCollateral);
    }

    function testHealthFactorisBrokenWhileDepositingAndMinting() external {
        (, int price, , , ) = MockV3Aggregator(wethUsdPriceFeed)
            .latestRoundData();
        uint256 amountToMint = (amountCollateral *
            (uint256(price) * dscEngine.getAdditionalFeedPrecision())) /
            dscEngine.getPrecision();

        uint256 expectedHealthFactor = dscEngine.calculateHealthFactor(
            amountToMint,
            dscEngine.getUsdValue(weth, amountCollateral)
        );

        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), amountCollateral);
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__BreaksHealthFactor.selector,
                expectedHealthFactor
            )
        );
        dscEngine.depositCollateralAndMintDsc(
            weth,
            amountCollateral,
            amountToMint
        );
        vm.stopPrank();
    }

    ///////////////////////////////////////
    // redeem Collateral Tests ////////////
    ///////////////////////////////////////

    modifier depositAndMintDsc() {
        (, int price, , , ) = MockV3Aggregator(wethUsdPriceFeed)
            .latestRoundData();
        uint256 amountToMint = ((amountCollateral *
            (uint256(price) * dscEngine.getAdditionalFeedPrecision())) /
            dscEngine.getPrecision()) / 2;

        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateralAndMintDsc(
            weth,
            amountCollateral,
            amountToMint
        );
        vm.stopPrank();

        _;
    }

    modifier depositAndMintDscUser2() {
        (, int price, , , ) = MockV3Aggregator(wethUsdPriceFeed)
            .latestRoundData();
        uint256 amountToMint = (((amountCollateral) *
            (uint256(price) * dscEngine.getAdditionalFeedPrecision())) /
            dscEngine.getPrecision());

        vm.startPrank(user2);
        ERC20Mock(weth).approve(address(dscEngine), amountCollateral * 6);
        dscEngine.depositCollateralAndMintDsc(
            weth,
            amountCollateral * 6,
            amountToMint
        );
        vm.stopPrank();

        _;
    }

    function testRedeemAmountShouldBeGreaterThanZero() external {
        vm.prank(user);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeGreaterThanZero.selector);
        dscEngine.redeemCollateral(weth, 0);
    }

    function testShouldRevertIfRedeemAmountIsGreaterThanActualDepositedAmount()
        external
        collateralDeposit
    {
        vm.prank(user);
        vm.expectRevert();
        dscEngine.redeemCollateral(weth, amountCollateral * 2);
    }

    function testRedeemFunctionShouldRevertIfHealthFactorGetsBroken()
        external
        depositAndMintDsc
    {
        (, int price, , , ) = MockV3Aggregator(wethUsdPriceFeed)
            .latestRoundData();
        uint256 amountToMint = ((amountCollateral *
            (uint256(price) * dscEngine.getAdditionalFeedPrecision())) /
            dscEngine.getPrecision()) / 2;

        uint256 redeemAmount = 1 ether;

        uint256 expectedHealthFactor = dscEngine.calculateHealthFactor(
            amountToMint,
            dscEngine.getUsdValue(weth, amountCollateral - redeemAmount)
        );

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__BreaksHealthFactor.selector,
                expectedHealthFactor
            )
        );
        dscEngine.redeemCollateral(weth, redeemAmount);
    }

    function testSuccessfullyRedeemsTheCollateral() external depositAndMintDsc {
        uint256 redeemAmount = 1 ether;
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateral(weth, amountCollateral);
        dscEngine.redeemCollateral(weth, redeemAmount);
        vm.stopPrank();
    }

    ///////////////////////////////////////
    // Burn Tests ////////////////////////
    ///////////////////////////////////////

    function testSuccessfulyBurnDsc() external depositAndMintDsc {
        uint256 burnAmount = 1000e18;
        // 10000,000000000000000000
        vm.startPrank(user);
        dsc.approve(address(dscEngine), burnAmount);
        dscEngine.burnDsc(burnAmount);
        vm.stopPrank();
    }

    function testShouldRevertIfNotApproved() external depositAndMintDsc {
        uint256 burnAmount = 1000e18;
        vm.startPrank(user);
        vm.expectRevert();
        dscEngine.burnDsc(burnAmount);
        vm.stopPrank();
    }

    function testShouldRevertForArithmeticUnderPass()
        external
        depositAndMintDsc
    {
        uint256 burnAmount = 100000e18;
        vm.startPrank(user);
        vm.expectRevert();
        dscEngine.burnDsc(burnAmount);
        vm.stopPrank();
    }

    //////////////////////////////////////////////
    // redeem Collateral for DSc Tests ////////////
    //////////////////////////////////////////////

    function testCollateralForMoreThanZero() external {
        uint256 redeemAmount = 0;
        vm.prank(user);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeGreaterThanZero.selector);
        dscEngine.redeemCollateralForDsc(weth, redeemAmount, redeemAmount);
    }

    function testRedeemCollateralRevertWhenHealthIsBroken()
        external
        depositAndMintDsc
    {
        (, int price, , , ) = MockV3Aggregator(wethUsdPriceFeed)
            .latestRoundData();
        uint256 amountToMint = ((amountCollateral *
            (uint256(price) * dscEngine.getAdditionalFeedPrecision())) /
            dscEngine.getPrecision()) / 2;

        uint256 redeemAmount = 5 ether;
        uint256 burnAmount = 1000 ether;
        uint256 expectedHealthFactor = dscEngine.calculateHealthFactor(
            amountToMint - burnAmount,
            dscEngine.getUsdValue(weth, amountCollateral - redeemAmount)
        );

        vm.startPrank(user);
        dsc.approve(address(dscEngine), burnAmount);

        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__BreaksHealthFactor.selector,
                expectedHealthFactor
            )
        );
        dscEngine.redeemCollateralForDsc(weth, redeemAmount, burnAmount);
        vm.stopPrank();
    }

    function testSuccessfullyReedemAndBurnCollateral()
        external
        depositAndMintDsc
    {
        uint256 burnAmount = 1000 ether;
        uint256 redeemAmount = 1 ether;
        vm.startPrank(user);
        dsc.approve(address(dscEngine), burnAmount);
        dscEngine.redeemCollateralForDsc(weth, redeemAmount, burnAmount);
        vm.stopPrank();
    }

    ///////////////////////////////
    // Liquidate tests ////////////
    ///////////////////////////////

    address public user2 = makeAddr("user2");

    function testRevertIfStartingHealthFactorisGreaterThanMinHealthFactor()
        external
        depositAndMintDsc
    {
        vm.prank(user2);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        dscEngine.liquidate(weth, user, 1 ether);
    }

    function testSuccessfullyLiquidatePositionforUser()
        external
        depositAndMintDsc
        depositAndMintDscUser2
    {
        uint256 userDscMintedAmount = dscEngine.getDscMintedAmount(user);
        int256 updatedEthUsdPrice = 1950e8;

        vm.startPrank(user2);
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(updatedEthUsdPrice);
        dsc.approve(address(dscEngine), userDscMintedAmount);
        dscEngine.liquidate(weth, user, userDscMintedAmount);
        vm.stopPrank();
    }

    function testPartialLiquidation()
        external
        depositAndMintDsc
        depositAndMintDscUser2
    {
        uint256 userDscMintedAmount = (dscEngine.getDscMintedAmount(user)) / 2;
        int256 updatedEthUsdPrice = 1950e8;

        vm.startPrank(user2);
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(updatedEthUsdPrice);
        dsc.approve(address(dscEngine), userDscMintedAmount);
        dscEngine.liquidate(weth, user, userDscMintedAmount);
        vm.stopPrank();
    }
}
