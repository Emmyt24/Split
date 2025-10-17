// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {SplitFactory} from "../src/splitContract.sol";

contract Deploy is Script {
    function run() external returns (SplitFactory) {
        vm.startBroadcast();
        SplitFactory factory = new SplitFactory();
        vm.stopBroadcast();
        return factory;
    }
}
