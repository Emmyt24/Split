// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/splitContract.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock ERC20 token for testing
contract MockERC20 is ERC20 {
    constructor() ERC20("MockToken", "MTK") {
        _mint(msg.sender, 1000000 * 10 ** decimals());
    }
}

contract SplitContractTest is Test {
    SplitContract split;
    SplitFactory factory;
    MockERC20 token;
    address owner = address(1);
    address treasury = address(2);
    address creator = address(3);
    address recipient1 = address(4);
    address recipient2 = address(5);
    address[] recipients;
    uint256[] percentages;

    function setUp() public {
        vm.startPrank(owner);
        factory = new SplitFactory();
        vm.stopPrank();

        token = new MockERC20();

        recipients = [recipient1, recipient2];
        percentages = [5000, 5000]; // 50% each

        vm.prank(creator);
        split = new SplitContract(
            recipients,
            percentages,
            creator,
            treasury
        );
    }

    // Test constructor
    function testConstructor() public {
        assertEq(split.splitCreator(), creator);
        assertEq(split.treasury(), treasury);
        assertEq(split.recipients(0), recipient1);
        assertEq(split.recipients(1), recipient2);
        assertEq(split.percentages(0), 5000);
        assertEq(split.percentages(1), 5000);
        assertFalse(split.finalized());
    }

    function testConstructorInvalidRecipients() public {
        address[] memory emptyRecipients = new address[](0);
        uint256[] memory emptyPercentages = new uint256[](0);
        vm.expectRevert(SplitContract.RecipientCountExceedsLimit.selector);
        new SplitContract(
            emptyRecipients,
            emptyPercentages,
            creator,
            treasury
        );
    }

    function testConstructorMismatchLengths() public {
        address[] memory rec = new address[](1);
        rec[0] = recipient1;
        uint256[] memory perc = new uint256[](2);
        perc[0] = 5000;
        perc[1] = 5000;
        vm.expectRevert(SplitContract.InvalidPercentageSum.selector);
        new SplitContract(rec, perc, creator, treasury);
    }

    // Test receive function
    function testReceiveETH() public {
        vm.deal(address(this), 1 ether);
        (bool success, ) = address(split).call{value: 1 ether}("");
        assertTrue(success);
        assertEq(address(split).balance, 1 ether);
    }

    function testReceiveETHZero() public {
        vm.expectRevert(SplitContract.AmountMustBeGreaterThanZero.selector);
        address(split).call{value: 0}("");
    }

    // Test distributeNative
    function testDistributeNative() public {
        vm.deal(address(split), 10000);
        uint256 initialTreasuryBalance = treasury.balance;
        uint256 initialRecipient1Balance = recipient1.balance;
        uint256 initialRecipient2Balance = recipient2.balance;

        vm.prank(creator);
        split.distributeNative();

        uint256 fee = (10000 * 50) / 10000; // 0.5%
        uint256 distributable = 10000 - fee;
        uint256 amountEach = distributable / 2;

        assertEq(treasury.balance, initialTreasuryBalance + fee);
        assertEq(recipient1.balance, initialRecipient1Balance + amountEach);
        assertEq(recipient2.balance, initialRecipient2Balance + amountEach);
        assertEq(split.nativeDistributed(), distributable);
    }

    function testDistributeNativeNoBalance() public {
        vm.prank(creator);
        vm.expectRevert(SplitContract.NoNativeToDistribute.selector);
        split.distributeNative();
    }

    function testDistributeNativeNotCreator() public {
        vm.deal(address(split), 10000);
        vm.expectRevert(SplitContract.InvalidCaller.selector);
        split.distributeNative();
    }

    function testDistributeNativeFinalized() public {
        vm.prank(creator);
        split.finalize();
        vm.deal(address(split), 10000);
        vm.prank(creator);
        vm.expectRevert(SplitContract.SplitAlreadyFinalized.selector);
        split.distributeNative();
    }

    // Test depositToken
    function testDepositToken() public {
        token.transfer(address(this), 1000);
        token.approve(address(split), 1000);
        split.depositToken(address(token), 1000);
        assertEq(token.balanceOf(address(split)), 1000);
    }

    function testDepositTokenZeroAmount() public {
        vm.expectRevert(SplitContract.AmountMustBeGreaterThanZero.selector);
        split.depositToken(address(token), 0);
    }

    function testDepositTokenInvalidToken() public {
        vm.expectRevert(SplitContract.InvalidTokenAddress.selector);
        split.depositToken(address(0), 100);
    }

    // Test distributeToken
    function testDistributeToken() public {
        token.transfer(address(split), 10000);
        uint256 initialTreasuryBalance = token.balanceOf(treasury);
        uint256 initialRecipient1Balance = token.balanceOf(recipient1);
        uint256 initialRecipient2Balance = token.balanceOf(recipient2);

        vm.prank(creator);
        split.distributeToken(address(token));

        uint256 fee = (10000 * 50) / 10000;
        uint256 distributable = 10000 - fee;
        uint256 amountEach = distributable / 2;

        assertEq(token.balanceOf(treasury), initialTreasuryBalance + fee);
        assertEq(
            token.balanceOf(recipient1),
            initialRecipient1Balance + amountEach
        );
        assertEq(
            token.balanceOf(recipient2),
            initialRecipient2Balance + amountEach
        );
        assertEq(split.tokenDistributed(), distributable);
    }

    function testDistributeTokenNoBalance() public {
        vm.prank(creator);
        vm.expectRevert(SplitContract.NoTokenToDistribute.selector);
        split.distributeToken(address(token));
    }

    // Test finalize
    function testFinalize() public {
        vm.prank(creator);
        split.finalize();
        assertTrue(split.finalized());
    }

    function testFinalizeNotCreator() public {
        vm.expectRevert(SplitContract.InvalidCaller.selector);
        split.finalize();
    }

    // Test withdrawRemaining
    function testWithdrawRemainingETH() public {
        vm.prank(creator);
        split.finalize();
        vm.deal(address(split), 1000);
        uint256 initialCreatorBalance = creator.balance;

        vm.prank(creator);
        split.withdrawRemaining(address(0));

        assertEq(creator.balance, initialCreatorBalance + 1000);
        assertEq(address(split).balance, 0);
    }

    function testWithdrawRemainingToken() public {
        vm.prank(creator);
        split.finalize();
        token.transfer(address(split), 1000);
        uint256 initialCreatorBalance = token.balanceOf(creator);

        vm.prank(creator);
        split.withdrawRemaining(address(token));

        assertEq(token.balanceOf(creator), initialCreatorBalance + 1000);
        assertEq(token.balanceOf(address(split)), 0);
    }

    function testWithdrawRemainingNotFinalized() public {
        vm.expectRevert(SplitContract.SplitNotFinalized.selector);
        vm.prank(creator);
        split.withdrawRemaining(address(0));
    }

    // Test view functions
    function testGetDetails() public {
        (
            address treas,
            address[] memory recs,
            uint256[] memory perc,
            uint256 nativeDist,
            uint256 tokDist,
            bool fin,
            uint256 created,
            uint256 fees,
            uint256 chain
        ) = split.getDetails();
        assertEq(treas, treasury);
        assertEq(recs.length, 2);
        assertEq(perc.length, 2);
        assertEq(nativeDist, 0);
        assertEq(tokDist, 0);
        assertFalse(fin);
    }

    function testGetRecipientCount() public {
        assertEq(split.getRecipientCount(), 2);
    }

    function testGetBalance() public {
        vm.deal(address(split), 500);
        token.transfer(address(split), 1000);
        uint256 nativeBal = split.getBalance(address(0));
        uint256 tokBal = split.getBalance(address(token));
        assertEq(nativeBal, 500);
        assertEq(tokBal, 1000);
    }
}

contract SplitFactoryTest is Test {
    SplitFactory factory;
    MockERC20 token;
    address owner = address(1);
    address creator = address(2);
    address recipient1 = address(3);
    address recipient2 = address(4);
    address[] recipients;
    uint256[] percentages;

    function setUp() public {
        vm.startPrank(owner);
        factory = new SplitFactory();
        vm.stopPrank();

        token = new MockERC20();
        recipients = [recipient1, recipient2];
        percentages = [5000, 5000];
    }

    // Test createSplit
    function testCreateSplit() public {
        vm.prank(creator);
        address splitAddr = factory.createSplit(
            recipients,
            percentages
        );

        assertTrue(factory.isSplit(splitAddr));
        assertEq(factory.splits(0), splitAddr);
        assertEq(factory.userSplits(creator, 0), splitAddr);
        assertEq(factory.getSplitCount(), 1);
    }

    function testCreateSplitInvalidPercentages() public {
        uint256[] memory invalidPerc = new uint256[](2);
        invalidPerc[0] = 3000;
        invalidPerc[1] = 3000; // sum != 10000
        vm.prank(creator);
        vm.expectRevert(SplitFactory.PercentageSumInvalid.selector);
        factory.createSplit(recipients, invalidPerc);
    }

    function testCreateSplitZeroPercentage() public {
        uint256[] memory zeroPerc = new uint256[](2);
        zeroPerc[0] = 0;
        zeroPerc[1] = 10000;
        vm.prank(creator);
        vm.expectRevert(SplitFactory.InvalidPercentage.selector);
        factory.createSplit(recipients, zeroPerc);
    }

    // Test emergencyWithdraw
    function testEmergencyWithdrawETH() public {
        vm.deal(address(factory), 1000);
        uint256 initialOwnerBalance = owner.balance;

        vm.prank(owner);
        factory.emergencyWithdraw(address(0), 1000);

        assertEq(owner.balance, initialOwnerBalance + 1000);
        assertEq(address(factory).balance, 0);
    }

    function testEmergencyWithdrawToken() public {
        token.transfer(address(factory), 1000);
        uint256 initialOwnerBalance = token.balanceOf(owner);

        vm.prank(owner);
        factory.emergencyWithdraw(address(token), 1000);

        assertEq(token.balanceOf(owner), initialOwnerBalance + 1000);
        assertEq(token.balanceOf(address(factory)), 0);
    }

    function testEmergencyWithdrawNotOwner() public {
        vm.deal(address(factory), 1000);
        vm.prank(creator);
        vm.expectRevert();
        factory.emergencyWithdraw(address(0), 1000);
    }

    // Test view functions
    function testGetUserSplits() public {
        vm.prank(creator);
        address splitAddr = factory.createSplit(
            recipients,
            percentages
        );

        address[] memory userSplits = factory.getUserSplits(creator);
        assertEq(userSplits.length, 1);
        assertEq(userSplits[0], splitAddr);
    }

    function testGetAllSplits() public {
        vm.prank(creator);
        address splitAddr = factory.createSplit(
            recipients,
            percentages
        );

        address[] memory allSplits = factory.getAllSplits();
        assertEq(allSplits.length, 1);
        assertEq(allSplits[0], splitAddr);
    }
}
