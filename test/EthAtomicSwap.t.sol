// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/EthAtomicSwap.sol";

contract EthAtomicSwapTest is Test {
    EthAtomicSwap htlc;
    bytes32 public constant SECRET = keccak256("secret-string");
    bytes32 public H;

    address alice = vm.addr(1);
    address bob   = vm.addr(2);

    function setUp() public {
        htlc = new EthAtomicSwap();
        H = sha256(abi.encodePacked(SECRET));
    }

    function testHappyPathETH() public {
        // Alice locks ETH
        vm.deal(alice, 5 ether);
        vm.prank(alice);
        htlc.lock{value: 1 ether}(H, bob, block.timestamp + 3 days, address(0), 0);

        // Bob mirrors; omitted for brevity

        // Alice claims on Zond → reveals SECRET
        vm.prank(bob);
        htlc.claim(abi.encodePacked(SECRET));

        // Balance assertions
        assertEq(bob.balance, 1 ether);
    }

    function testRefundAfterExpiry() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        htlc.lock{value: 1 ether}(H, bob, block.timestamp + 1, address(0), 0);

        // Fast‑forward past expiry
        vm.warp(block.timestamp + 2);

        vm.prank(alice);
        htlc.refund(H);

        assertEq(alice.balance, 1 ether);
    }
}
