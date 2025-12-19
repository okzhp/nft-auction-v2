// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol"; // 引入测试库，类似 import org.junit.Test;
import {MyNFT} from "../src/MyNFT.sol";

contract MyNFTTest is Test {
    MyNFT public myNFT;
    address public owner; 
    address public alice; 
    address public bob;

    function setUp() public {
        owner = makeAddr("owner_zhp");
        alice = makeAddr("alice_zhp");
        bob = makeAddr("bob_zhp");

        vm.prank(owner);
        myNFT = new MyNFT();
    }

    function testInitState() public {
        assertEq(myNFT.name(), "ZhpNFT");
        assertEq(myNFT.symbol(), "ZNFT");
    }

    function testMintNft() public {
        string memory uri = "test";
        vm.prank(owner);
        uint256 tokenId = myNFT.safeMintNft(alice, uri);

        assertEq(myNFT.ownerOf(tokenId), alice);

        //非owner调用期望revert
        vm.prank(bob);
        vm.expectRevert();
        myNFT.safeMintNft(alice, uri);
    }

    function testTransfer() public {
        string memory uri = "test";
        vm.prank(owner);
        uint256 tokenId = myNFT.safeMintNft(alice, uri);

        vm.prank(alice);
        myNFT.safeTransferFrom(alice, bob, tokenId);
        assertEq(myNFT.ownerOf(tokenId), bob);

    }


}