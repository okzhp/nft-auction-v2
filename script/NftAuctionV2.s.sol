// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {NftAuctionV2} from "../src/NftAuctionV2.sol";
/**
在根目录下 创建.env文件并配置PRIVATE_KEY，
执行部署命令：
forge script script/NftAuctionV2.s.sol:NftAuctionV2Script \
    --rpc-url https://eth-sepolia.g.alchemy.com/v2/QyTJFlHI_6sViFRorM5P0 \
    --broadcast \
    --verify \
    --etherscan-api-key RW8YCITMY1B84VV2MXW4DURK3HTCEAFEXN

 */
contract NftAuctionV2Script is Script {
    // --- Sepolia 配置 ---
    // 官方 USDC 合约地址
    address constant USDC_ADDR = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
    // Chainlink USDC/USD Feed
    address constant USDC_USD_FEED = 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E; 
    // Chainlink ETH/USD Feed
    address constant ETH_USD_FEED = 0x694AA1769357215DE4FAC081bf1f309aDC325306;

    function setUp() public {}

    function run() public {
        // 1. 获取部署者的私钥
        // 必须在 .env 文件中配置 PRIVATE_KEY=你的私钥
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // 2. 只有在 Sepolia 网络上才执行（防止误部署到主网）
        // Sepolia ChainID 是 11155111
        if (block.chainid != 11155111) {
            console.log("Warning: You are NOT on Sepolia chain!");
            // 如果你想强行部署，可以注释掉下面这行
            // return; 
        }

        console.log("Deploying on chain ID:", block.chainid);
        console.log("Deployer address:", vm.addr(deployerPrivateKey));

        // 3. 开始广播交易
        vm.startBroadcast(deployerPrivateKey);

        // 4. 部署合约
        NftAuctionV2 auction = new NftAuctionV2(
            USDC_ADDR,
            USDC_USD_FEED,
            ETH_USD_FEED
        );

        // 5. 停止广播
        vm.stopBroadcast();

        // 6. 输出结果
        console.log("--------------------------------------------------");
        console.log("NftAuctionV2 deployed successfully!");
        console.log("Contract Address:", address(auction));
        console.log("--------------------------------------------------");
    }
}
