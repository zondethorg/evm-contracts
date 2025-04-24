// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../src/EthAtomicSwap.sol"; // path to the contract
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/*//////////////////////////////////////////////////////////////
                          Mocks
//////////////////////////////////////////////////////////////*/
contract MockERC20 is ERC20 {
    constructor() ERC20("Mock", "MOCK") {
        _mint(msg.sender, 1_000_000 ether);
    }
}

/*//////////////////////////////////////////////////////////////
                        Test Suite
//////////////////////////////////////////////////////////////*/
contract EthAtomicSwapTest is Test {
    EthAtomicSwap swap;
    MockERC20 token;

    address alice = vm.addr(1); // locker / initiator
    address bob = vm.addr(2); // recipient / counter-party
    address nobody = vm.addr(3); // random address

    bytes bobAddrBytes = bytes("Z2019EA08f4e24201B98f9154906Da4b924A04892");
    bytes desiredAsset = bytes("Z332AC2A198CA80A371F4c47d44aAA0f887C251dD");
    bytes32 secret = keccak256("super-secret"); // <-- 32-byte secret
    bytes32 hashSecret = sha256(abi.encodePacked(secret)); // SHA-256 pre-image
    uint256 amountEth = 1 ether;
    uint256 amountErc20 = 500 ether;
    uint256 desiredAmount = 777_000;

    /*//////////////////////////////////////////////////////////////
                               SET-UP
    //////////////////////////////////////////////////////////////*/
    function setUp() public {
        vm.deal(alice, 1000 ether);
        vm.deal(bob, 1000 ether);

        // deploy swap contract with alice as the owner for pause rights
        vm.prank(alice);
        swap = new EthAtomicSwap();

        token = new MockERC20();
        token.transfer(alice, 600 ether); // give alice some ERC-20
    }

    /*//////////////////////////////////////////////////////////////
                         Helper: lock + derive ID
    //////////////////////////////////////////////////////////////*/
    function _lockETH() internal returns (bytes32 swapID) {
        vm.prank(alice);
        swapID = swap.lock{value: amountEth}(
            hashSecret,
            bob,
            block.timestamp + 1 days,
            address(0), // ETH
            0, // ignored for ETH
            desiredAsset,
            desiredAmount
        );
    }

    function _lockERC20() internal returns (bytes32 swapID) {
        vm.startPrank(alice);
        token.approve(address(swap), amountErc20);
        swapID = swap.lock(
            hashSecret, bob, block.timestamp + 1 days, address(token), amountErc20, desiredAsset, desiredAmount
        );
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                          Happy Paths
    //////////////////////////////////////////////////////////////*/
    function testLockEthAndClaim() public {
        uint256 balBefore = bob.balance;
        bytes32 swapID = _lockETH();

        vm.expectEmit(true, true, true, true);
        emit EthAtomicSwap.Claimed(swapID, abi.encodePacked(secret));

        vm.prank(bob);
        swap.claim(swapID, abi.encodePacked(secret));

        assertEq(bob.balance, balBefore + amountEth);
        (,,,,,,, bool claimed) = swap.swaps(swapID);
        assertTrue(claimed);
    }

    function testLockERC20AndClaim() public {
        bytes32 swapID = _lockERC20();

        // Verify swapID matches previewSwapID
        bytes32 expectedSwapID = swap.previewSwapID(alice, hashSecret, bob);
        assertEq(swapID, expectedSwapID);

        uint256 balBefore = token.balanceOf(bob);
        vm.prank(bob);
        swap.claim(swapID, abi.encodePacked(secret));

        assertEq(token.balanceOf(bob), balBefore + amountErc20);
        (,,,,,,, bool claimed) = swap.swaps(swapID);
        assertTrue(claimed);
    }

    /*//////////////////////////////////////////////////////////////
                           Refund Path
    //////////////////////////////////////////////////////////////*/
    function testRefundAfterExpiry() public {
        uint256 balBefore = alice.balance;

        bytes32 swapID = _lockETH();

        // warp past expiry
        vm.warp(block.timestamp + 2 days);

        vm.prank(alice);
        swap.refund(swapID);

        assertEq(alice.balance, balBefore);
        (,,,,,,, bool claimed) = swap.swaps(swapID);
        assertTrue(claimed);
    }

    /*//////////////////////////////////////////////////////////////
                         Failure Scenarios
    //////////////////////////////////////////////////////////////*/
    function testCannotClaimWithWrongSecret() public {
        bytes32 swapID = _lockETH();
        vm.prank(bob);
        vm.expectRevert("AS: wrong secret");
        swap.claim(swapID, abi.encodePacked("bad-secret"));
    }

    function testCannotRefundBeforeExpiry() public {
        bytes32 swapID = _lockETH();

        vm.prank(alice);
        vm.expectRevert("AS: not expired");
        swap.refund(swapID);
    }

    function testNonLockerCannotRefund() public {
        bytes32 swapID = _lockETH();
        vm.warp(block.timestamp + 2 days);

        vm.prank(bob);
        vm.expectRevert("AS: not locker");
        swap.refund(swapID);
    }

    function testDoubleClaimGuard() public {
        bytes32 swapID = _lockERC20();

        vm.prank(bob);
        swap.claim(swapID, abi.encodePacked(secret));

        vm.prank(bob);
        vm.expectRevert("AS: already claimed");
        swap.claim(swapID, abi.encodePacked(secret));
    }

    /*//////////////////////////////////////////////////////////////
                       Preview ID Helper Check
    //////////////////////////////////////////////////////////////*/
    function testPreviewSwapIDMatches() public {
        bytes32 predicted = swap.previewSwapID(alice, hashSecret, bob);
        bytes32 actual = _lockETH();
        assertEq(predicted, actual);
    }
}
