//SPDX-License-Identifier:MIT

pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {console} from "forge-std/console.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

/**
 * @title DSC Engine
 * @author Amarnath
 * The system is designed to be as minimal as possible, and have tokens maintain a 1token = 1$ peg.
 * The StableCoin has properties:
 * 1. Exogenous Collateral
 * 2. Dollar Pegged
 * 3. Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees , and was only backed by WETH and WBTC.
 *
 * Our DSC System should be overcollateralized. At no point, should the
 * value of all the collateral <= $ backed value of all the DSC.
 *
 * @notice This contract is the core of the DSC system.It handles all the logic for mining and redeeming'
 * DSC, as well as depositing & withdrawing collateral.
 * @notice This contract is very loosely based on MakerDAO DSS(DAI) System
 */

contract DSCEngine is ReentrancyGuard {
    //////////////////////////////////
    ///////   Errors   ///////////////
    //////////////////////////////////

    error DSCEngine__MustBeGreaterThanZero();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__TokenCollateralAddressesAndPriceFeedAddressesMustBeOfSameLength();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();

    //////////////////////////////////
    ///////   Type   /////////////////
    //////////////////////////////////
    using OracleLib for AggregatorV3Interface;

    ///////////////////////////////////////////
    ///////   State variables   ///////////////
    ///////////////////////////////////////////

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; // this means a 10% bonus

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount))
        private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinter) private s_DscMinted;

    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_Dsc;

    //////////////////////////////////
    ///////   Events   ///////////////
    //////////////////////////////////
    event CollateralDeposited(
        address indexed user,
        address indexed token,
        uint256 indexed amount
    );

    event CollateralRedeemed(
        address indexed from,
        address indexed to,
        address indexed tokenCollateral,
        uint256 redeemedAmount
    );

    //////////////////////////////////
    ///////   Modifiers   ////////////
    //////////////////////////////////
    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine__MustBeGreaterThanZero();
        }
        _;
    }

    modifier isAllowedToken(address _token) {
        if (s_priceFeeds[_token] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }

    //////////////////////////////////
    ///////   Functions   ////////////
    //////////////////////////////////

    constructor(
        address[] memory tokenCollateralAddresses,
        address[] memory priceFeedAddresses,
        address _DSCAddress
    ) {
        if (tokenCollateralAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenCollateralAddressesAndPriceFeedAddressesMustBeOfSameLength();
        }

        for (uint256 i = 0; i < tokenCollateralAddresses.length; ++i) {
            s_priceFeeds[tokenCollateralAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenCollateralAddresses[i]);
        }

        i_Dsc = DecentralizedStableCoin(_DSCAddress);
    }

    //////////////////////////////////////////
    ///////   ExternalFunctions   ////////////
    //////////////////////////////////////////

    /**
     *
     * @param tokenCollateralAddress Address of the token to deposit as a collateral
     * @param collateralAmount Amount of the collateral to be deposited
     * @param amountDscToMint Amount of the Decentralized Stable Coin to be minted
     * @notice This function will deposit your collateral and mint DSC in one transaction
     */

    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 collateralAmount,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, collateralAmount);
        mintDsc(amountDscToMint);
    }

    /**
     * @notice follows CEI pattern
     * @param tokenCollateralAddress The address of the token to deposit as a collateral
     * @param collateralAmount Amount of the collateral to deposit
     */
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 collateralAmount
    )
        public
        moreThanZero(collateralAmount)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][
            tokenCollateralAddress
        ] += collateralAmount;
        emit CollateralDeposited(
            msg.sender,
            tokenCollateralAddress,
            collateralAmount
        );
        bool success = IERC20(tokenCollateralAddress).transferFrom(
            msg.sender,
            address(this),
            collateralAmount
        );
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     *
     * @param tokenCollateral Address of the collateral to be redeemed.
     * @param redeemAmount Amount of the collateral to be redeemed.
     * @param dscBurnAmount Amount of the Stablecoin to be burned.
     */

    function redeemCollateralForDsc(
        address tokenCollateral,
        uint256 redeemAmount,
        uint256 dscBurnAmount
    ) external moreThanZero(redeemAmount) {
        burnDsc(dscBurnAmount);
        redeemCollateral(tokenCollateral, redeemAmount);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     *
     * @param tokenCollateral The collateral which the user want to redeem
     * @param redeemAmount The amount of the collateral that is to be redeemed.
     */
    function redeemCollateral(
        address tokenCollateral,
        uint256 redeemAmount
    ) public moreThanZero(redeemAmount) {
        _redeemCollateral(
            msg.sender,
            msg.sender,
            tokenCollateral,
            redeemAmount
        );

        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function burnDsc(uint256 burnAmount) public moreThanZero(burnAmount) {
        _burnDsc(burnAmount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function mintDsc(
        uint256 amountDscToMint
    ) public moreThanZero(amountDscToMint) {
        s_DscMinted[msg.sender] += amountDscToMint;
        // let's say if the minted amount is too much then
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_Dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    /**
     *
     * We do need the system to be overcollateralized hence, if the collateral value stoops below the given threshold
     * , getting lower than the minimum Health Factor Then an external person can liquidate the user's debtt position.
     *
     * Liquidators will be incentivized to liquidate user's position in form of bonusses.
     *
     * @param tokenCollateral The collateral to liquidate
     * @param user Address of the user who has the broken health Factor.
     * @param debtToCover Amount of the DSC you want to burn to improve the user's health Factor
     * @notice you can partically liquidiate a user.
     * @notice You will get a liqudation bonus on taking the user's funds.
     * @notice This function assumes that the protocol will be atleast 200% overcollateralized.
     */

    function liquidate(
        address tokenCollateral,
        address user,
        uint256 debtToCover
    ) external {
        uint256 startingHealthFactor = _healthFactor(user);
        if (startingHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(
            tokenCollateral,
            debtToCover
        );

        uint256 bonusCollateral = (tokenAmountFromDebtCovered *
            LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;

        uint256 totalCollateralToReedem = tokenAmountFromDebtCovered +
            bonusCollateral;

        _redeemCollateral(
            user,
            msg.sender,
            tokenCollateral,
            totalCollateralToReedem
        );

        _burnDsc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (startingHealthFactor >= endingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getHealthFactor() external {}

    //////////////////////////////////////////////////////////
    ///////   Private and Internal Functions   ///////////////
    //////////////////////////////////////////////////////////

    /**
     *
     * @param amountToBurn The amount of Dsc to burn
     * @param onBehalfOf Who's Dsc is going to be burned ( user's)
     * @param dscFrom Who's giving the Dsc instead of user to cover the user's position
     * the function calling this function should check whether the health Factor is broken or not
     */

    function _burnDsc(
        uint256 amountToBurn,
        address onBehalfOf,
        address dscFrom
    ) private {
        s_DscMinted[onBehalfOf] -= amountToBurn;
        bool success = i_Dsc.transferFrom(dscFrom, address(this), amountToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_Dsc.burn(amountToBurn);
    }

    function _redeemCollateral(
        address from,
        address to,
        address tokenCollateral,
        uint redeemAmount
    ) private {
        s_collateralDeposited[from][tokenCollateral] -= redeemAmount;
        emit CollateralRedeemed(from, to, tokenCollateral, redeemAmount);
        // check if the health Factor is broken or not
        bool success = IERC20(tokenCollateral).transfer(to, redeemAmount);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _getAccountInformation(
        address user
    )
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValuedInUsd)
    {
        totalDscMinted = s_DscMinted[user];
        collateralValuedInUsd = getAccountCollateralValue(user);
    }

    function _calculateHealthFactor(
        uint256 totalDscMinted,
        uint256 collateralValueInUsd
    ) internal pure returns (uint256) {
        if (totalDscMinted == 0) return type(uint256).max;

        // the collateral should be overcollateralized
        uint256 collateralAdjustedForThreshold = (LIQUIDATION_THRESHOLD *
            collateralValueInUsd) / LIQUIDATION_PRECISION;

        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    /**
     *
     * Returns how close to liquidation a user is
     * If a user goes below 1e18, then they can get liquidated
     */

    function _healthFactor(address user) private view returns (uint256) {
        // total DSC Minted
        // total Collateral Value
        (
            uint256 totalDSCMinted,
            uint256 collateralValueinUSD
        ) = _getAccountInformation(user);

        return _calculateHealthFactor(totalDSCMinted, collateralValueinUSD);
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        // 1. Check the health factor
        // 2. Revert if they don't
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    //////////////////////////////////////////////////////////////
    ///////   Public and External view Functions   ///////////////
    //////////////////////////////////////////////////////////////

    function getTokenAmountFromUsd(
        address tokenCollateral,
        uint256 usdAmountInWei
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[tokenCollateral]
        );
        (, int256 price, , , ) = priceFeed.staleCheckLatestRoundData();
        return ((usdAmountInWei * PRECISION) /
            (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }

    function getAccountCollateralValue(
        address user
    ) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; ++i) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.staleCheckLatestRoundData();
        return
            ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getAccountInformation(
        address user
    )
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValuedInUsd)
    {
        return _getAccountInformation(user);
    }

    function calculateHealthFactor(
        uint256 totalDscMinted,
        uint256 collateralValueInUsd
    ) external pure returns (uint256) {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    // getter functions
    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getDscMintedAmount(address user) external view returns (uint256) {
        return s_DscMinted[user];
    }

    function getCollateralBalance(
        address collateral,
        address user
    ) external view returns (uint256) {
        return s_collateralDeposited[user][collateral];
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }
}
