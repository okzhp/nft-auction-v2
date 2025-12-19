// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {
    IERC721Receiver
} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";


/**
这是一个拍卖合约的版本V2，
和普通版本的区别在于，
此版本可以使用以太币和USDC进行支付拍卖，
需调用Chainlink实时查询币种价格并进行计算
*/
contract NftAuctionV2 is Ownable, IERC721Receiver {
    //拍卖状态
    enum AuctionState {
        Preparing,
        Begin,
        End
    }

    //拍卖持续时间 分钟
    uint256 public durationMinutes;
    //拍卖结束时间
    uint256 public endTime;
    //拍卖状态
    AuctionState public state;

    //卖家
    address public seller;
    //nft合约地址
    address public nft;
    //nft tokenID
    uint256 public tokenId;

    //以太币 出价map
    mapping(address => uint256) public ethMap;
    //usdc 出价map
    mapping (address => uint256) public usdcMap;

    //当前出最高价者
    address public currentBuyer;
    //当前最高出价 转换为 => usd
    uint256 public currentPrice;

    //usdc代币 合约地址
    IERC20 public immutable usdcToken;
    //usdc => usd
    AggregatorV3Interface public immutable usdcPriceFeed;
    //eth => usd
    AggregatorV3Interface public immutable ethPriceFeed;

    event CreateAuction(
        address indexed seller,
        address indexed nft,
        uint256 tokenId,
        uint256 durationMinutes
    );
    event BidUSD(address indexed buyer, uint256 bid);
    event AuctionEnd(address indexed buyer, uint256 bid);

    constructor(address _usdcToken, address _usdcFeed, address _ethFeed) Ownable(msg.sender) {
        state = AuctionState.Preparing;
        usdcToken = IERC20(_usdcToken);
        usdcPriceFeed = AggregatorV3Interface(_usdcFeed);
        ethPriceFeed = AggregatorV3Interface(_ethFeed);
    }

    modifier inState(AuctionState _state) {
        _inState(_state);
        _;
    }

    function _inState(AuctionState _state) internal view {
        require(_state == state, "invalid AuctionState");
    }

    //创建拍卖，仅owner可创建
    function createAuction(
        address _nft,
        uint256 _tokenId,
        uint256 _durationMinutes
    ) public onlyOwner inState(AuctionState.Preparing) {
        require(_durationMinutes > 0, "_durationMinutes must greater than 0");
        require(IERC721(_nft).ownerOf(_tokenId) == msg.sender,"not nft owner");

        //将nft转移到本合约
        IERC721(_nft).safeTransferFrom(msg.sender, address(this), _tokenId);

        //属性赋值
        seller = msg.sender;
        nft = _nft;
        tokenId = _tokenId;
        durationMinutes = _durationMinutes;
        endTime = block.timestamp + _durationMinutes * 1 minutes;
        state = AuctionState.Begin;

        emit CreateAuction(seller, _nft, _tokenId, _durationMinutes);
    }

    //出价 可以用ehter或usdc，可以同时使用
    function bid(uint256 usdcAmount) public payable inState(AuctionState.Begin) {
        require(block.timestamp < endTime, "over endTime");
        
        if(msg.value > 0) {
            ethMap[msg.sender] += msg.value;
        }
        
        if(usdcAmount > 0) {
            bool success = usdcToken.transferFrom(msg.sender, address(this), usdcAmount);
            require(success, "bid transfer usdc fail");
            usdcMap[msg.sender] += usdcAmount;
        }

        uint256 newPrice = calculateTotalPrice(msg.sender);

        require(newPrice > currentPrice, "bid must greater than currentPrice");

        if(currentBuyer != msg.sender) {
            currentBuyer = msg.sender;
        }
        currentPrice = newPrice;

        emit BidUSD(msg.sender, newPrice);
    }

    //计算eth和usdc的总价值，返回USD，保留18位小数
    function calculateTotalPrice(address _user) public view returns (uint256) {
        uint256 totalAmount;
        
        uint256 ethAmount = ethMap[_user];
        if(ethAmount > 0) {
            totalAmount += (ethAmount * getLatestETHPrice() / 1e8);
        }

        uint256 usdcAmount = usdcMap[_user];
        if(usdcAmount > 0 ) {
            totalAmount += (usdcAmount * getLatestUSDCPrice() * 1e12 / 1e8);
        }

        return totalAmount;
    }


    //实时查询usdc => usd
    function getLatestUSDCPrice() public view returns (uint256) {
        (
            /* uint80 roundID */,
            int256 price,
            /* uint256 startedAt */,
            uint256 timeStamp,
            /* uint80 answeredInRound */
        ) = usdcPriceFeed.latestRoundData();
        require(price > 0, "Invalid USDC price");
        // 确保价格是最近 1 小时内更新的 (Chainlink 心跳通常是 1小时 或 偏差阈值触发)
        // require(block.timestamp - timeStamp < 3600, "Stale price");

        // Chainlink 返回的是 int256，且有 8 位小数（例如 $2000 会返回 200000000000）
        return uint256(price);
    }

    //实时查询ether => usd
    function getLatestETHPrice() public view returns (uint256) {
        (
            /* uint80 roundID */,
            int256 price,
            /* uint256 startedAt */,
            uint256 timeStamp,
            /* uint80 answeredInRound */
        ) = ethPriceFeed.latestRoundData();
        require(price > 0, "Invalid ETH price");
        // 确保价格是最近 1 小时内更新的 (Chainlink 心跳通常是 1小时 或 偏差阈值触发)
        // require(block.timestamp - timeStamp < 3600, "Stale price");

        // Chainlink 返回的是 int256，且有 8 位小数（例如2858 38047200）
        return uint256(price);
    }

    //敲定
    function finalize() public onlyOwner inState(AuctionState.Begin) {
        require(block.timestamp >= endTime, "wait for endTime");
        
        state = AuctionState.End;

        //转移nft到最高出价者，如果流拍，归还至卖家
        if (currentBuyer == address(0)) {
            IERC721(nft).safeTransferFrom(address(this), seller, tokenId);
            emit AuctionEnd(address(0), 0);
        } else {
            //转移nft给买家
            IERC721(nft).safeTransferFrom(address(this), currentBuyer, tokenId);
            
            //转移以太币给卖家
            uint256 ethValue = ethMap[currentBuyer];
            if(ethValue > 0) {
                ethMap[currentBuyer] = 0;
                (bool success, ) = payable(seller).call{value: ethValue}("");
                require(success, "transfer ether fail");
            }

            //转移usdc给卖家
            uint256 usdcValue = usdcMap[currentBuyer];
            if(usdcValue > 0) {
                usdcMap[currentBuyer] = 0;
                bool success = usdcToken.transfer(seller, usdcValue);
                require(success, "transfer usdc fail");
            }
            
            emit AuctionEnd(currentBuyer, currentPrice);
        }
    }

    //给未竞拍成功者进行退款 pull-push模式,需用户主动调用
    function withDraw() public {
        if(state == AuctionState.Begin && msg.sender == currentBuyer) {
            revert("You are the highest bidder, funds locked!");
        }
        uint256 ethValue = ethMap[msg.sender];
        uint256 usdcValue = usdcMap[msg.sender];

        require(ethValue > 0 || usdcValue > 0, "insufficient balance");
        
        if(ethValue > 0) {
            ethMap[msg.sender] = 0;
            (bool success, ) = payable(msg.sender).call{value: ethValue}("");
            require(success, "withdraw transfer ether fail");
        }
        
        if(usdcValue > 0) {
            usdcMap[msg.sender] = 0;
            bool success = usdcToken.transfer(msg.sender, usdcValue);
            require(success, "withdraw transfer usdc fail");
        }
    }

    // 实现 onERC721Received，允许合约接收 NFT
    function onERC721Received(
        address _operator,
        address _from,
        uint256 _tokenId,
        bytes calldata _data
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
