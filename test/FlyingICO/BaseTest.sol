// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/src/Test.sol";
import {FlyingICO} from "../../src/FlyingICO.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockChainlinkPriceFeed} from "../mocks/MockChainlinkPriceFeed.sol";

/**
 * @title BaseTest
 * @dev Base contract for FlyingICO tests containing common setup and declarations
 */
contract BaseTest is Test {
    FlyingICO public ico;
    MockERC20 public usdc;
    MockERC20 public weth;
    MockChainlinkPriceFeed public usdcPriceFeed;
    MockChainlinkPriceFeed public wethPriceFeed;
    MockChainlinkPriceFeed public ethPriceFeed;

    address public treasury = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    address public user3 = address(0x4);

    address public sequencer = address(0); // Set to 0 for mainnet-like behavior (no sequencer check)
    uint256[] public frequencies = new uint256[](3);

    uint256 public constant TOKEN_CAP = 1000000; // 1M tokens
    uint256 public constant TOKENS_PER_USD = 10; // 10 tokens per $1 USD
    uint256 public constant WAD = 1e18;

    uint256 public vestingStart;
    uint256 public vestingEnd;

    // Price feeds return prices with 8 decimals (standard Chainlink format)
    // USDC: $1 = 1e8 (1 USD with 8 decimals)
    // WETH: $2000 = 2000e8
    // ETH: $2000 = 2000e8
    int256 public constant USDC_PRICE = 1e8; // $1
    int256 public constant WETH_PRICE = 2000e8; // $2000
    int256 public constant ETH_PRICE = 2000e8; // $2000

    // Events
    event FlyingICO__Initialized(
        string name,
        string symbol,
        uint256 tokenCap,
        uint256 tokensPerUsd,
        address[] acceptedAssets,
        address[] priceFeeds,
        uint256[] frequencies,
        address sequencer,
        address treasury,
        uint256 vestingStart,
        uint256 vestingEnd
    );
    event FlyingICO__Invested(
        address indexed user, uint256 positionId, address asset, uint256 assetAmount, uint256 tokensMinted
    );
    event FlyingICO__Divested(
        address indexed user,
        uint256 positionId,
        uint256 tokensBurned,
        address assetReturned,
        uint256 assetReturnedAmount
    );
    event FlyingICO__Unlocked(
        address indexed user,
        uint256 positionId,
        uint256 tokensUnlocked,
        address assetReleased,
        uint256 assetReleasedAmount
    );

    function setUp() public virtual {
        // Deploy mock tokens
        usdc = new MockERC20("USD Coin", "USDC", 6);
        weth = new MockERC20("Wrapped Ether", "WETH", 18);

        // Deploy mock price feeds
        usdcPriceFeed = new MockChainlinkPriceFeed(8, USDC_PRICE);
        wethPriceFeed = new MockChainlinkPriceFeed(8, WETH_PRICE);
        ethPriceFeed = new MockChainlinkPriceFeed(8, ETH_PRICE);

        // Setup accepted assets and price feeds
        address[] memory acceptedAssets = new address[](3);
        acceptedAssets[0] = address(usdc);
        acceptedAssets[1] = address(weth);
        acceptedAssets[2] = address(0);

        address[] memory priceFeeds = new address[](3);
        priceFeeds[0] = address(usdcPriceFeed);
        priceFeeds[1] = address(wethPriceFeed);
        priceFeeds[2] = address(ethPriceFeed);

        frequencies[0] = 1 hours;
        frequencies[1] = 1 hours;
        frequencies[2] = 1 hours;

        vestingStart = block.timestamp + 1 days;
        vestingEnd = block.timestamp + 30 days;

        // Deploy ICO
        ico = new FlyingICO(
            "Flying Token",
            "FLY",
            TOKEN_CAP,
            TOKENS_PER_USD,
            acceptedAssets,
            priceFeeds,
            frequencies,
            sequencer,
            treasury,
            vestingStart,
            vestingEnd
        );

        // Give users some tokens
        usdc.mint(user1, 1000000e6);
        usdc.mint(user2, 1000000e6);
        usdc.mint(user3, 1000000e6);
        weth.mint(user1, 1000e18);
        weth.mint(user2, 1000e18);
        weth.mint(user3, 1000e18);

        // Give users ETH
        vm.deal(user1, 1000 ether);
        vm.deal(user2, 1000 ether);
        vm.deal(user3, 1000 ether);
    }
}

