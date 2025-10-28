// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title SplitContract
 * @notice Multi-chain payment splitting contract for Base and Celo
 * @dev Supports native tokens (ETH/CELO) and stablecoins (USDC, cUSD)
 */
contract SplitContract is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Events
    event NativeReceived(address indexed from, uint256 amount);
    event NativeDistributed(uint256 totalAmount, uint256 feeCollected);
    event TokenReceived(address indexed token, address indexed from, uint256 amount);
    event TokenDistributed(address indexed token, uint256 totalAmount, uint256 feeCollected);
    event RecipientPaid(address indexed recipient, address indexed token, uint256 amount);
    event RecipientPaymentFailed(address indexed recipient, address indexed token, uint256 amount);
    event SplitFinalized(uint256 timestamp);
    event DustSentToTreasury(address indexed token, uint256 amount);
    event SplitMetadataUpdated(string metadata);

    // Constants
    uint256 public constant BASIS_POINTS_SCALE = 10000;
    uint256 public constant FEE_BASIS_POINTS = 50; // 0.5% fee
    uint256 public constant MAX_RECIPIENTS = 100;

    // State variables
    address public immutable splitCreator;
    address public immutable treasury;
    address public immutable token; // ERC20 token address (address(0) for native token)
    uint256 public immutable chainId; // Chain ID for multi-chain tracking
    uint256 public immutable createdAt;
    
    address[] public recipients;
    uint256[] public percentages;
    string public metadata; // JSON metadata

    uint256 public nativeDistributed;
    uint256 public tokenDistributed;
    uint256 public totalFeesCollected;
    bool public finalized;

    // Custom errors
    error InvalidCaller();
    error SplitAlreadyFinalized();
    error NoTokenToDistribute();
    error InvalidSplitCreator();
    error NoNativeToDistribute();
    error AmountMustBeGreaterThanZero();
    error RecipientCountExceedsLimit();
    error InvalidRecipientAddress();
    error InvalidTreasuryAddress();
    error InvalidPercentageSum();
    error TransferFailed();
    error SplitNotFinalized();
    error InvalidTokenAddress();

    // Modifiers
    modifier onlySplitCreator() {
        if (msg.sender != splitCreator) revert InvalidCaller();
        _;
    }

    modifier notFinalized() {
        if (finalized) revert SplitAlreadyFinalized();
        _;
    }

    constructor(
        address[] memory _recipients,
        uint256[] memory _percentages,
        address _splitCreator,
        address _treasury,
        address _token
    ) {
        if (_recipients.length == 0) revert RecipientCountExceedsLimit();
        if (_recipients.length > MAX_RECIPIENTS) revert RecipientCountExceedsLimit();
        if (_recipients.length != _percentages.length) revert InvalidPercentageSum();
        if (_splitCreator == address(0)) revert InvalidSplitCreator();
        if (_treasury == address(0)) revert InvalidTreasuryAddress();

        uint256 totalPercentage;
        uint256 length = _recipients.length;
        for (uint256 i; i < length;) {
            if (_percentages[i] == 0) revert InvalidPercentageSum();
            if (_recipients[i] == address(0)) revert InvalidRecipientAddress();
            unchecked {
                totalPercentage += _percentages[i];
                ++i;
            }
        }
        if (totalPercentage != BASIS_POINTS_SCALE) revert InvalidPercentageSum();

        splitCreator = _splitCreator;
        treasury = _treasury;
        token = _token;
        recipients = _recipients;
        percentages = _percentages;
        createdAt = block.timestamp;
        chainId = block.chainid;
    }

    receive() external payable {
        if (msg.value == 0) revert AmountMustBeGreaterThanZero();
        emit NativeReceived(msg.sender, msg.value);
    }

    function depositNative(uint256 amount) external payable notFinalized {
        if (msg.value != amount) revert AmountMustBeGreaterThanZero();
        emit NativeReceived(msg.sender, amount);
    }

    function distributeNative() external onlySplitCreator nonReentrant notFinalized {
        uint256 balance = address(this).balance;
        if (balance == 0) revert NoNativeToDistribute();

        uint256 fee = (balance * FEE_BASIS_POINTS) / BASIS_POINTS_SCALE;
        uint256 distributableAmount;
        unchecked {
            distributableAmount = balance - fee;
        }

        (bool feeSuccess, ) = payable(treasury).call{value: fee}("");
        if (!feeSuccess) revert TransferFailed();

        uint256 amountDistributed;
        uint256 length = recipients.length;

        for (uint256 i; i < length;) {
            uint256 amount = (distributableAmount * percentages[i]) / BASIS_POINTS_SCALE;
            if (amount > 0) {
                (bool successRecipient, ) = payable(recipients[i]).call{value: amount}("");
                if (successRecipient) {
                    unchecked {
                        amountDistributed += amount;
                    }
                    emit RecipientPaid(recipients[i], address(0), amount);
                } else {
                    emit RecipientPaymentFailed(recipients[i], address(0), amount);
                }
            }
            unchecked {
                ++i;
            }
        }

        uint256 remaining;
        unchecked {
            remaining = distributableAmount - amountDistributed;
        }
        if (remaining > 0) {
            (bool dustSuccess, ) = payable(treasury).call{value: remaining}("");
            if (dustSuccess) {
                emit DustSentToTreasury(address(0), remaining);
            }
        }

        unchecked {
            nativeDistributed += amountDistributed;
            totalFeesCollected += fee;
        }
        emit NativeDistributed(amountDistributed, fee);
    }

    function depositToken(uint256 amount) external notFinalized {
        if (token == address(0)) revert InvalidTokenAddress();
        if (amount == 0) revert AmountMustBeGreaterThanZero();
        
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        emit TokenReceived(token, msg.sender, amount);
    }

    function distributeToken() external onlySplitCreator nonReentrant notFinalized {
        if (token == address(0)) revert InvalidTokenAddress();
        
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance == 0) revert NoTokenToDistribute();

        uint256 fee = (balance * FEE_BASIS_POINTS) / BASIS_POINTS_SCALE;
        uint256 distributableAmount;
        unchecked {
            distributableAmount = balance - fee;
        }

        IERC20(token).safeTransfer(treasury, fee);

        uint256 amountDistributed;
        uint256 length = recipients.length;

        for (uint256 i; i < length;) {
            uint256 amount = (distributableAmount * percentages[i]) / BASIS_POINTS_SCALE;
            if (amount > 0) {
                IERC20(token).safeTransfer(recipients[i], amount);
                unchecked {
                    amountDistributed += amount;
                }
                emit RecipientPaid(recipients[i], token, amount);
            }
            unchecked {
                ++i;
            }
        }

        uint256 remaining;
        unchecked {
            remaining = distributableAmount - amountDistributed;
        }
        if (remaining > 0) {
            IERC20(token).safeTransfer(treasury, remaining);
            emit DustSentToTreasury(token, remaining);
        }

        unchecked {
            tokenDistributed += amountDistributed;
            totalFeesCollected += fee;
        }
        emit TokenDistributed(token, amountDistributed, fee);
    }

    function updateMetadata(string memory _metadata) external onlySplitCreator {
        metadata = _metadata;
        emit SplitMetadataUpdated(_metadata);
    }

    function finalize() external onlySplitCreator {
        finalized = true;
        emit SplitFinalized(block.timestamp);
    }

    function withdrawRemaining(address tokenAddress) external onlySplitCreator {
        if (!finalized) revert SplitNotFinalized();
        
        if (tokenAddress == address(0)) {
            uint256 nativeBalance = address(this).balance;
            if (nativeBalance == 0) revert NoNativeToDistribute();
            
            (bool success, ) = payable(splitCreator).call{value: nativeBalance}("");
            if (!success) revert TransferFailed();
        } else {
            if (tokenAddress != token) revert InvalidTokenAddress();
            uint256 tokenBalance = IERC20(token).balanceOf(address(this));
            if (tokenBalance == 0) revert NoTokenToDistribute();
            
            IERC20(token).safeTransfer(splitCreator, tokenBalance);
        }
    }

    function getDetails()
        external
        view
        returns (
            address _treasury,
            address _token,
            address[] memory _recipients,
            uint256[] memory _percentages,
            uint256 _nativeDistributed,
            uint256 _tokenDistributed,
            bool _finalized,
            uint256 _createdAt,
            uint256 _totalFees,
            uint256 _chainId
        )
    {
        return (
            treasury,
            token,
            recipients,
            percentages,
            nativeDistributed,
            tokenDistributed,
            finalized,
            createdAt,
            totalFeesCollected,
            chainId
        );
    }

    function getRecipientCount() external view returns (uint256) {
        return recipients.length;
    }

    function getBalances()
        external
        view
        returns (uint256 nativeAmount, uint256 tokenAmount)
    {
        nativeAmount = address(this).balance;
        tokenAmount = token == address(0) ? 0 : IERC20(token).balanceOf(address(this));
    }

}

/**
 * @title SplitFactory
 * @notice Multi-chain factory for Base and Celo deployments
 */
contract SplitFactory is Ownable(msg.sender), ReentrancyGuard {
    using SafeERC20 for IERC20;

    address[] public splits;
    mapping(address => bool) public isSplit;

    uint256 public totalSplitsCreated;
    uint256 public immutable CHAIN_ID;

    event SplitCreated(
        address indexed splitAddress,
        address indexed creator,
        address token,
        address[] recipients,
        uint256[] percentages,
        uint256 timestamp,
        uint256 chainId
    );

    error InvalidRecipientCount();
    error LengthMismatch();
    error InvalidPercentage();
    error PercentageSumInvalid();

    constructor() {
        CHAIN_ID = block.chainid;
    }

    function createSplit(
        address token,
        address[] memory recipients,
        uint256[] memory percentages
    ) external nonReentrant returns (address) {
        if (recipients.length == 0) revert InvalidRecipientCount();
        if (recipients.length != percentages.length) revert LengthMismatch();

        uint256 totalPercentage;
        uint256 length = recipients.length;
        for (uint256 i; i < length;) {
            if (percentages[i] == 0) revert InvalidPercentage();
            unchecked {
                totalPercentage += percentages[i];
                ++i;
            }
        }
        if (totalPercentage != 10000) revert PercentageSumInvalid();

        SplitContract newSplit = new SplitContract(
            recipients,
            percentages,
            msg.sender,
            owner(),
            token
        );
        
        address splitAddress = address(newSplit);
        splits.push(splitAddress);
        isSplit[splitAddress] = true;
        unchecked {
            ++totalSplitsCreated;
        }

        emit SplitCreated(
            splitAddress,
            msg.sender,
            token,
            recipients,
            percentages,
            block.timestamp,
            CHAIN_ID
        );

        return splitAddress;
    }


    function getSplitCount() external view returns (uint256) {
        return splits.length;
    }




    function isValidSplit(address splitAddress) external view returns (bool) {
        return isSplit[splitAddress];
    }

    receive() external payable {}
}