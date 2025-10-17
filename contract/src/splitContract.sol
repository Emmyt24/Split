// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SplitContract is ReentrancyGuard {
    using SafeERC20 for IERC20;

    event ETHReceived(address indexed from, uint256 amount);
    event ETHDistributed(uint256 totalAmount);
    event TokenReceived(
        address indexed token,
        address indexed from,
        uint256 amount
    );
    event TokenDistributed(address indexed token, uint256 totalAmount);
    event RecipientPaid(
        address indexed recipient,
        address indexed token,
        uint256 amount
    );
    event RecipientPaymentFailed(
        address indexed recipient,
        address indexed token,
        uint256 amount
    );
    event SplitFinalized(uint256 timestamp);
    event DustSentToTreasury(address indexed token, uint256 amount);

    uint256 public constant BASIS_POINTS_SCALE = 10000;
    uint256 public constant FEE_BASIS_POINTS = 50; // 0.5% fee

    address public splitCreator;
    address public treasury;
    address public token; // ERC20 token address (address(0) for ETH-only)
    address[] public recipients;
    uint256[] public percentages; // in base points

    uint256 public ethDistributed;
    uint256 public tokenDistributed;
    bool public finalized;

    error invalid_caller();
    error split_NotFinalized();
    error no_Token_to_Distribute();
    error invalid_split_creator();
    error no_Eth_To_Distribute();
    error Amount_must_be_greater_Zero();
    error recipient_must_be_greater_than_Zero();
    error recipient_and_Percentage_length_not_the_same();

    modifier onlySplitCreator() {
        if (msg.sender != splitCreator) {
            revert invalid_caller();
        }
        _;
    }

    modifier notFinalized() {
        if (finalized) {
            revert split_NotFinalized();
        }
        _;
    }

    constructor(
        address[] memory _recipients,
        uint256[] memory _percentages,
        address _splitCreator,
        address _treasury,
        address _token
    ) {
        require(_recipients.length > 0, "Must have at least one recipient");
        require(
            _recipients.length == _percentages.length,
            "Recipients and percentages length mismatch"
        );
        require(_splitCreator != address(0), "Invalid split creator");
        require(_treasury != address(0), "Invalid treasury address");
        splitCreator = _splitCreator;
        treasury = _treasury;
        token = _token;
        recipients = _recipients;
        percentages = _percentages;
    }

    receive() external payable {
        require(msg.value > 0, "must send ETH");
        emit ETHReceived(msg.sender, msg.value);
    }

    function distributeEth()
        external
        onlySplitCreator
        nonReentrant
        notFinalized
    {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH to distribute");

        // Calculate fee (0.5% of total balance)
        uint256 fee = (balance * FEE_BASIS_POINTS) / BASIS_POINTS_SCALE;
        uint256 distributableAmount = balance - fee;

        // Transfer fee to treasury
        (bool success, ) = payable(treasury).call{value: fee}("");
        require(success, "Fee transfer to treasury failed");

        uint256 amountDistributed = 0;
        for (uint256 i = 0; i < recipients.length; i++) {
            uint256 amount = (distributableAmount * percentages[i]) /
                BASIS_POINTS_SCALE;
            if (amount > 0) {
                (bool successRecipient, ) = payable(recipients[i]).call{
                    value: amount
                }("");
                if (successRecipient) {
                    amountDistributed += amount;
                    emit RecipientPaid(recipients[i], address(0), amount);
                } else {
                    emit RecipientPaymentFailed(
                        recipients[i],
                        address(0),
                        amount
                    );
                }
            }
        }
        // Handle dust: send remaining to treasury
        uint256 remaining = distributableAmount - amountDistributed;
        if (remaining > 0) {
            (bool successTreasury, ) = payable(treasury).call{value: remaining}(
                ""
            );
            if (successTreasury) {
                emit DustSentToTreasury(address(0), remaining);
            }
        }
        ethDistributed += amountDistributed;
        emit ETHDistributed(amountDistributed);
    }

    function depositToken(uint256 amount) external notFinalized {
        require(token != address(0), "No token set for this split");
        require(amount > 0, "Amount must be greater than zero");
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        emit TokenReceived(token, msg.sender, amount);
    }

    function distributeToken()
        external
        onlySplitCreator
        nonReentrant
        notFinalized
    {
        require(token != address(0), "No token set for this split");
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance > 0, "No token to distribute");

        // Calculate fee (0.5% of total balance)
        uint256 fee = (balance * FEE_BASIS_POINTS) / BASIS_POINTS_SCALE;
        uint256 distributableAmount = balance - fee;

        // Transfer fee to treasury
        IERC20(token).safeTransfer(treasury, fee);

        uint256 amountDistributed = 0;
        for (uint256 i = 0; i < recipients.length; i++) {
            uint256 amount = (distributableAmount * percentages[i]) /
                BASIS_POINTS_SCALE;
            if (amount > 0) {
                IERC20(token).safeTransfer(recipients[i], amount);
                amountDistributed += amount;
                emit RecipientPaid(recipients[i], token, amount);
            }
        }
        // Handle dust: send remaining to treasury
        uint256 remaining = distributableAmount - amountDistributed;
        if (remaining > 0) {
            IERC20(token).safeTransfer(treasury, remaining);
            emit DustSentToTreasury(token, remaining);
        }
        tokenDistributed += amountDistributed;
        emit TokenDistributed(token, amountDistributed);
    }

    function finalize() external onlySplitCreator {
        finalized = true;
        emit SplitFinalized(block.timestamp);
    }

    function withdrawRemaining(address tokenAddress) external onlySplitCreator {
        require(finalized, "Split not finalized");
        if (tokenAddress == address(0)) {
            uint256 ethBalance = address(this).balance;
            require(ethBalance > 0, "No ETH to withdraw");
            (bool success, ) = payable(splitCreator).call{value: ethBalance}(
                ""
            );
            require(success, "ETH withdrawal failed");
        } else {
            require(tokenAddress == token, "Invalid token address");
            uint256 tokenBalance = IERC20(token).balanceOf(address(this));
            require(tokenBalance > 0, "No tokens to withdraw");
            IERC20(token).safeTransfer(splitCreator, tokenBalance);
        }
    }

    function getDetails()
        external
        view
        returns (
            address,
            address,
            address[] memory,
            uint256[] memory,
            uint256,
            uint256,
            bool
        )
    {
        return (
            treasury,
            token,
            recipients,
            percentages,
            ethDistributed,
            tokenDistributed,
            finalized
        );
    }

    function getRecipientCount() external view returns (uint256) {
        return recipients.length;
    }

    function getBalances()
        external
        view
        returns (uint256 ethAmount, uint256 tokenAmount)
    {
        ethAmount = address(this).balance;
        tokenAmount = token == address(0)
            ? 0
            : IERC20(token).balanceOf(address(this));
    }
}

contract SplitFactory is Ownable(msg.sender), ReentrancyGuard {
    address[] public splits;
    mapping(address => address[]) public userSplits; // creator => splits
    mapping(address => bool) public isSplit; // quick lookup

    // Events
    event SplitCreated(
        address indexed splitAddress,
        address indexed creator,
        address token,
        address[] recipients,
        uint256[] percentages,
        uint256 timestamp
    );

    function createSplit(
        address token,
        address[] memory recipients,
        uint256[] memory percentages
    ) external nonReentrant returns (address){
        require(recipients.length > 0, "Must have at least one recipient");
        require(
            recipients.length == percentages.length,
            "Recipients and percentages length must match"
        );

        // Verify percentage sum to 10000
        uint256 totalPercentage = 0;
        for (uint256 i = 0; i < percentages.length; i++) {
            require(percentages[i] > 0, "Percentage must be greater than 0");
            totalPercentage += percentages[i];
        }
        require(totalPercentage == 10000, "Percentages must sum to 10000");

        // Create new split contract
        SplitContract newSplit = new SplitContract(
            recipients,
            percentages,
            msg.sender,
            owner(), // treasury is the factory owner
            token
        );
        address splitAddress = address(newSplit);
        splits.push(splitAddress);
        userSplits[msg.sender].push(splitAddress);
        isSplit[splitAddress] = true;
        emit SplitCreated(
            splitAddress,
            msg.sender,
            token,
            recipients,
            percentages,
            block.timestamp
        );
        return splitAddress;
    }

    function emergencyWithdraw(
        address token,
        uint256 amount
    ) external onlyOwner nonReentrant {
        if (token == address(0)) {
            require(
                amount <= address(this).balance,
                "Insufficient ETH balance"
            );
            (bool success, ) = payable(owner()).call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            require(
                amount <= IERC20(token).balanceOf(address(this)),
                "Insufficient token balance"
            );
            IERC20(token).transfer(owner(), amount);
        }
    }

    function getSplitCount() external view returns (uint256) {
        return splits.length;
    }

    function getUserSplits(
        address user
    ) external view returns (address[] memory) {
        return userSplits[user];
    }

    function getAllSplits() external view returns (address[] memory) {
        return splits;
    }

    receive() external payable {}
}
