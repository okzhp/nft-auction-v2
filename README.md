# 项目简介
- 这是一个基于foundry框架开发的NFT铸造、拍卖合约，可以铸造ERC721的NFT，并对NFT进行拍卖。
- 支持NFT的铸造、转移等符合ERC721标准的操作
- 支持对NFT的拍卖，支持以太币和USDC支付，通过chainlink实时查询代币价值。

# 结构说明
主要关注三个目录：
- script: 部署脚本
- src: 合约代码。MyNFT是铸造NFT合约、NftAuctionV2是拍卖合约。
- test: 合约测试用例

# 使用说明
1. 将项目clone到本地。由于lib文件夹是指向别的仓库的链接，因此clone时需要使用：
`git clone --recursive https://github.com/okzhp/nft-auction-v2.git`
> 如果已经执行了`git clone https://github.com/okzhp/nft-auction-v2.git`,需要再次执行`git submodule update --init --recursive`
2. 调整合约文件/测试用例(如果需要).
3. 查看gas消耗。执行`forge snapshot --fork-url https://eth-sepolia.g.alchemy.com/v2/你的私钥 -vv`，可选参数 --check，用来对比gas前后消耗对比。
3. 测试。执行`forge test --fork-url https://eth-sepolia.g.alchemy.com/v2/你的私钥 -vv` 执行单元测试。
4. 部署。执行`forge script script/NftAuctionV2.s.sol:NftAuctionV2Script \
    --rpc-url https://eth-sepolia.g.alchemy.com/v2/你的私钥 \
    --broadcast \
    --verify \
    --etherscan-api-key 你的私钥`部署到sepolia

> 由于需要用到sepolia链上数据，因此通常需要在命令后加上`--fork-url https://eth-sepolia.g.alchemy.com/v2/你的私钥`用来使用sepolia链上数据。