// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {SplitFactory} from "../src/splitContract.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        SplitFactory factory = new SplitFactory();
        
        console.log("SplitFactory deployed to:", address(factory));
        console.log("Chain ID:", block.chainid);
        
        vm.stopBroadcast();
    }
}