// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {
    IERC721Receiver
} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

/**
这是一个普通版本的拍卖合约，
允许合约部署者拍卖自己的一个NFT， 
此版本只允许以太币进行拍卖，
是一个典型的英式拍卖。
*/
contract NftAuction is Ownable, IERC721Receiver {
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

    //出价map
    mapping(address => uint256) priceMap;
    //当前出最高价者
    address public currentBuyer;
    //当前最高出价
    uint256 public currentPrice;

    event CreateAuction(
        address indexed seller,
        address indexed nft,
        uint256 tokenId,
        uint256 durationMinutes
    );
    event Bid(address indexed buyer, uint256 bid);
    event AuctionEnd(address indexed buyer, uint256 bid);

    constructor() Ownable(msg.sender) {
        state = AuctionState.Preparing;
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

    //出价 
    function bid() public payable inState(AuctionState.Begin) {
        require(block.timestamp < endTime, "over endTime");
        uint256 historyBid = priceMap[msg.sender];
        uint256 newPrice = historyBid + msg.value;
        require(newPrice > currentPrice, "bid must greater than currentPrice");

        if(currentBuyer != msg.sender) {
            currentBuyer = msg.sender;
        }
        currentPrice = newPrice;
        priceMap[msg.sender] = newPrice;

        emit Bid(msg.sender, newPrice);
    }

    //敲定
    function finalize() public inState(AuctionState.Begin) {
        require(block.timestamp >= endTime, "wait for endTime");
        
        state = AuctionState.End;

        //转移nft到最高出价者，如果流拍，归还至卖家
        if (currentBuyer == address(0)) {
            IERC721(nft).safeTransferFrom(address(this), seller, tokenId);
            emit AuctionEnd(address(0), 0);
        } else {
            //转移nft给买家
            IERC721(nft).safeTransferFrom(address(this), currentBuyer, tokenId);
            
            priceMap[currentBuyer] = 0; 
            //转移拍卖价格给卖家
            (bool success, ) = payable(seller).call{value: currentPrice}("");
            require(success, "transfer ether fail");

            emit AuctionEnd(currentBuyer, currentPrice);
        }
    }

    //给未竞拍成功者进行退款 pull-push模式,需用户主动调用
    function withDraw() public {
        if(state == AuctionState.Begin && msg.sender != currentBuyer) {
            revert("You are the highest bidder, funds locked!");
        }

        uint256 balance = priceMap[msg.sender];
        require(balance > 0, "insufficient balance");

        //CEI模式退款
        priceMap[msg.sender] = 0;
        
        //退款
        (bool success, ) = payable(address(msg.sender)).call{value: balance}(
            ""
        );
        require(success, "transfer ether fail");
    }

    // 实现 onERC721Received，允许合约接收 NFT
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
