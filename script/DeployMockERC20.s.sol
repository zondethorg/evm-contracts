// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../src/MockERC20.sol";

contract DeployMockERC20 is Script {
    address deployedMockERC20;

    function run() external {
        vm.startBroadcast();
        deployedMockERC20 = address(new MockERC20("MockERC20", "MRC20", 18, 1000000000000000000000000));
        console.log("Deployed MockERC20: %s", deployedMockERC20);
        vm.stopBroadcast();
    }
}
