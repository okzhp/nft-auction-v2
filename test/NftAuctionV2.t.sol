// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol"; // 引入测试库，类似 import org.junit.Test;
import {NftAuctionV2, Ownable, IERC20} from "../src/NftAuctionV2.sol";
import {MyNFT} from "../src/MyNFT.sol";

/**
这个单测覆盖了核心场景和所有的正常操作，
但有一个缺陷，如果sepolia上ether->usd波动太大可能会导致测试失败，
因为出价时金额是固定的，可能由于波动导致没有符合预期。
可优化点：
1、使用MockV3Aggregator固定价格
2、记录初始和结束时的余额，确保到账
3、丰富其他场景测试
 */

//通过 --fork-url 使用sepolia链上数据
//forge test --fork-url https://eth-sepolia.g.alchemy.com/v2/QyTJFlHI_6sViFRorM5P0 -vv
contract NftAuctionV2Test is Test {
    NftAuctionV2 public auctionV2;
    MyNFT public myNFT;
    uint256 public tokenId;

    //用来deal一些usdc币
    address USDC_ADDRESS = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;

    address public owner; 
    address public alice; 
    address public bob;

    function setUp() public {
        owner = makeAddr("owner_zhp");
        alice = makeAddr("alice_zhp");
        bob = makeAddr("bob_zhp");

        vm.prank(owner);
        //sepolia上 usdc合约地址、usdc->usd、ether->usd
        auctionV2 = new NftAuctionV2(
            address(0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238),
            address(0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E),
            address(0x694AA1769357215DE4FAC081bf1f309aDC325306)
            );

        vm.prank(owner);
        myNFT = new MyNFT();
        
        //给owner铸造一个nft
        vm.prank(owner);
        tokenId = myNFT.safeMintNft(owner, "test");

        // //先授权nft转移给拍卖合约，否则后续无法创建合约
        vm.prank(owner);
        myNFT.approve(address(auctionV2), tokenId);
    }

    //测试创建合约
    function test_createAuction() public{
        //非owner创建拍卖，期望报错
        vm.prank(alice);
        bytes memory expectErr = abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice);
        vm.expectRevert(expectErr);
        auctionV2.createAuction(address(myNFT), tokenId, 10);

        //owner创建拍卖 正常
        vm.prank(owner);
        auctionV2.createAuction(address(myNFT), tokenId, 10);
        
        assertEq(auctionV2.nft(), address(myNFT));
        assertEq(auctionV2.tokenId(), tokenId);
        assertEq(auctionV2.durationMinutes(), 10);
        //期望nft所有权归合约所有
        assertEq(myNFT.ownerOf(tokenId), address(auctionV2));
    }

    //测试出价 仅使用eth
    function test_bid_ether() public {
        vm.prank(owner);
        auctionV2.createAuction(address(myNFT), tokenId, 10);

        vm.deal(bob, 10 ether);
        vm.deal(alice, 10 ether);

        //bob出价5 ether
        vm.prank(bob);
        auctionV2.bid{value: 5 ether}(0);
        assertEq(auctionV2.currentBuyer(), bob);
        assertEq(auctionV2.ethMap(bob), 5 ether);

        //bob出价2 ether
        vm.prank(bob);
        auctionV2.bid{value: 2 ether}(0);
        assertEq(auctionV2.currentBuyer(), bob);
        assertEq(auctionV2.ethMap(bob), 7 ether);

        //alice出价7 erher 期望异常
        vm.prank(alice);
        vm.expectRevert("bid must greater than currentPrice");
        auctionV2.bid{value: 7 ether}(0);

        //alice出价8 erher 
        vm.prank(alice);
        auctionV2.bid{value: 8 ether}(0);
        assertEq(auctionV2.currentBuyer(), alice);
        assertEq(auctionV2.ethMap(alice), 8 ether);

        //非最高价进行退款
        vm.prank(bob);
        auctionV2.withDraw();
        assertEq(auctionV2.ethMap(bob), 0);
        assertEq(auctionV2.usdcMap(bob), 0);

    }

    //测试出价 仅使用usdc
    function test_bid_usdc() public {
        vm.prank(owner);
        auctionV2.createAuction(address(myNFT), tokenId, 10);

        // --- 上帝操作开始 ---
        
        // 语法: deal(token地址, 接收者地址, 数量)
        // 给 Alice 凭空变出 10,000 USDC (注意 USDC 是 6 位精度)
        deal(USDC_ADDRESS, alice, 10000 * 1e6);
        deal(USDC_ADDRESS, bob, 10000 * 1e6);
        
        // --- 上帝操作结束 ---
        // 验证一下
        // console.log("Alice USDC Balance:", IERC20(USDC_ADDRESS).balanceOf(alice));
        // assertEq(IERC20(USDC_ADDRESS).balanceOf(alice), 10000 * 1e6);


        //usdc 授权额度
        vm.startPrank(bob);
        auctionV2.usdcToken().approve(address(auctionV2), 300 * 1e6);
        vm.stopPrank();

        vm.startPrank(alice);
        auctionV2.usdcToken().approve(address(auctionV2), 400 * 1e6);
        vm.stopPrank();


        //bob出价100 
        vm.prank(bob);
        auctionV2.bid(100 * 1e6);
        assertEq(auctionV2.currentBuyer(), bob);
        assertEq(auctionV2.usdcMap(bob), 100 * 1e6);

        //bob出价200 usdc
        vm.prank(bob);
        auctionV2.bid(200 * 1e6);
        assertEq(auctionV2.currentBuyer(), bob);
        assertEq(auctionV2.usdcMap(bob), 300 * 1e6);

        //alice出价300 usdc 期望异常
        vm.prank(alice);
        vm.expectRevert("bid must greater than currentPrice");
        auctionV2.bid(300 * 1e6);

        // //alice出价400 usdc
        vm.prank(alice);
        auctionV2.bid(400 * 1e6);
        assertEq(auctionV2.currentBuyer(), alice);
        assertEq(auctionV2.usdcMap(alice), 400 * 1e6);

        //非最高价进行退款
        vm.prank(bob);
        auctionV2.withDraw();
        assertEq(auctionV2.ethMap(bob), 0);
        assertEq(auctionV2.usdcMap(bob), 0);
    }

    //一个较完整的混合出价、敲定、退款测试
    function test_bid_mix() public {
        vm.prank(owner);
        auctionV2.createAuction(address(myNFT), tokenId, 10);

        vm.deal(bob, 10 ether);
        vm.deal(alice, 10 ether);

        deal(USDC_ADDRESS, alice, 10000 * 1e6);
        deal(USDC_ADDRESS, bob, 10000 * 1e6);
        
        //usdc 授权额度
        vm.startPrank(bob);
        auctionV2.usdcToken().approve(address(auctionV2), 10000 * 1e6);
        vm.stopPrank();

        vm.startPrank(alice);
        auctionV2.usdcToken().approve(address(auctionV2), 10000 * 1e6);
        vm.stopPrank();

        //=========开始出价===================
        //bob出价1 ether
        vm.prank(bob);
        auctionV2.bid{value: 1 ether}(0);

        //price出价4000usdc 
        vm.prank(alice);
        auctionV2.bid(4000 * 1e6);
        assertEq(auctionV2.currentBuyer(), alice);
        assertEq(auctionV2.ethMap(bob), 1 ether);
        assertEq(auctionV2.usdcMap(alice), 4000 * 1e6);

        //bob 加价2000usdt
        vm.prank(bob);
        auctionV2.bid(2000 * 1e6);
        assertEq(auctionV2.currentBuyer(), bob);
        assertEq(auctionV2.ethMap(bob), 1 ether);
        assertEq(auctionV2.usdcMap(bob), 2000 * 1e6);
        assertEq(auctionV2.usdcMap(alice), 4000 * 1e6);

        //alice加价2 ether
        vm.prank(alice);
        auctionV2.bid{value: 2 ether}(0);
        assertEq(auctionV2.currentBuyer(), alice);
        assertEq(auctionV2.ethMap(bob), 1 ether);
        assertEq(auctionV2.ethMap(alice), 2 ether);
        assertEq(auctionV2.usdcMap(bob), 2000 * 1e6);
        assertEq(auctionV2.usdcMap(alice), 4000 * 1e6);

        //结束前 敲定 预期异常
        vm.prank(owner);
        vm.expectRevert("wait for endTime");
        auctionV2.finalize();
        assertEq(uint8(auctionV2.state()), 1);

        //结束前 最高价者退款 预期异常
        vm.prank(alice);
        vm.expectRevert("You are the highest bidder, funds locked!");
        auctionV2.withDraw();


        //经过20分钟 
        vm.warp(block.timestamp + 20 * 1 minutes);

        //结束后 敲定 预期成功
        vm.prank(owner);
        auctionV2.finalize();
        assertEq(uint8(auctionV2.state()), 2);
        assertEq(auctionV2.ethMap(alice), 0);
        assertEq(auctionV2.usdcMap(alice), 0);

        //nft所属owner -> alice
        assertEq(myNFT.ownerOf(tokenId), alice);

        //结束后 正常退款
        vm.prank(bob);
        auctionV2.withDraw();
        assertEq(auctionV2.ethMap(bob), 0);
        assertEq(auctionV2.usdcMap(bob), 0);
        
    }
}