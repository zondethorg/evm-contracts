// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../src/EthAtomicSwap.sol";

contract DeployEthAtomicSwap is Script {
    address deployedEthAtomicSwap;

    function run() external {
        vm.startBroadcast();
        deployedEthAtomicSwap = address(new EthAtomicSwap());
        console.log("Deployed EthAtomicSwap: %s", deployedEthAtomicSwap);
        vm.stopBroadcast();
    }
}
