// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

interface IStrategyManager {
    function totalDeployedAssets() external view returns (uint256);
    function harvest() external returns (uint256 profit);
    function deployAssets(uint256 amount) external;
    function withdrawAssets(uint256 amount) external returns (uint256 actual);
    function emergencyWithdrawAll() external returns (uint256 recovered);
}

/**
 * @title MeridianVault
 * @notice ERC-4626 compliant vault with multi-strategy yield optimization,
 *         auto-compounding, risk scoring, emergency withdrawal, and fee structure.
 * @dev Designed for HashKey Chain (EVM-compatible). Delegates yield generation
 *      to a pluggable StrategyManager contract.
 */
contract MeridianVault is ERC4626, Ownable2Step, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    // ──────────────────────────────────────────────
    //  Constants
    // ──────────────────────────────────────────────

    uint256 public constant MAX_MANAGEMENT_FEE = 500;      // 5 %  (basis points)
    uint256 public constant MAX_PERFORMANCE_FEE = 3000;     // 30 %
    uint256 public constant FEE_DENOMINATOR = 10_000;
    uint256 public constant COMPOUND_COOLDOWN = 1 hours;
    uint256 public constant MAX_DEPOSIT_LIMIT = type(uint256).max;

    // ──────────────────────────────────────────────
    //  State
    // ──────────────────────────────────────────────

    IStrategyManager public strategyManager;

    uint256 public managementFee;       // annual fee in basis points
    uint256 public performanceFee;      // fee on profits in basis points
    address public feeRecipient;

    uint256 public lastCompoundTimestamp;
    uint256 public lastFeeCollectionTimestamp;
    uint256 public lastHarvestProfit;
    uint256 public totalProfitAccrued;

    uint256 public depositLimit;        // 0 = unlimited
    uint256 public highWaterMark;       // for performance-fee tracking

    bool public emergencyMode;

    // Per-user risk scoring (off-chain AI updates on-chain via keeper)
    mapping(address => uint8) public strategyRiskScore; // 1-100

    // ──────────────────────────────────────────────
    //  Events
    // ──────────────────────────────────────────────

    event StrategyManagerUpdated(address indexed oldManager, address indexed newManager);
    event FeesUpdated(uint256 managementFee, uint256 performanceFee);
    event FeeRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);
    event DepositLimitUpdated(uint256 newLimit);
    event Harvested(uint256 profit, uint256 performanceFeeTaken, uint256 timestamp);
    event Compounded(uint256 amountRedeployed, uint256 timestamp);
    event EmergencyModeActivated(address indexed caller, uint256 recoveredAssets);
    event EmergencyModeDeactivated(address indexed caller);
    event EmergencyWithdrawal(address indexed user, uint256 shares, uint256 assets);
    event RiskScoreUpdated(address indexed strategy, uint8 newScore);
    event AssetsDeployed(uint256 amount);
    event AssetsWithdrawn(uint256 requested, uint256 actual);

    // ──────────────────────────────────────────────
    //  Errors
    // ──────────────────────────────────────────────

    error ExceedsDepositLimit();
    error NoStrategyManager();
    error InvalidFee();
    error InvalidAddress();
    error CompoundCooldown();
    error EmergencyModeActive();
    error EmergencyModeNotActive();
    error ZeroAmount();
    error InsufficientIdleBalance(uint256 requested, uint256 available);

    // ──────────────────────────────────────────────
    //  Constructor
    // ──────────────────────────────────────────────

    constructor(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        address feeRecipient_,
        uint256 managementFee_,
        uint256 performanceFee_
    )
        ERC4626(asset_)
        ERC20(name_, symbol_)
        Ownable(msg.sender)
    {
        if (feeRecipient_ == address(0)) revert InvalidAddress();
        if (managementFee_ > MAX_MANAGEMENT_FEE) revert InvalidFee();
        if (performanceFee_ > MAX_PERFORMANCE_FEE) revert InvalidFee();

        feeRecipient = feeRecipient_;
        managementFee = managementFee_;
        performanceFee = performanceFee_;
        depositLimit = MAX_DEPOSIT_LIMIT;
        lastCompoundTimestamp = block.timestamp;
        lastFeeCollectionTimestamp = block.timestamp;
    }

    // ──────────────────────────────────────────────
    //  Admin setters
    // ──────────────────────────────────────────────

    function setStrategyManager(address manager_) external onlyOwner {
        if (manager_ == address(0)) revert InvalidAddress();
        address old = address(strategyManager);
        strategyManager = IStrategyManager(manager_);

        // Approve the new manager to pull the underlying asset
        IERC20(asset()).forceApprove(manager_, type(uint256).max);

        emit StrategyManagerUpdated(old, manager_);
    }

    function setFees(uint256 mgmt, uint256 perf) external onlyOwner {
        if (mgmt > MAX_MANAGEMENT_FEE) revert InvalidFee();
        if (perf > MAX_PERFORMANCE_FEE) revert InvalidFee();
        managementFee = mgmt;
        performanceFee = perf;
        emit FeesUpdated(mgmt, perf);
    }

    function setFeeRecipient(address recipient) external onlyOwner {
        if (recipient == address(0)) revert InvalidAddress();
        address old = feeRecipient;
        feeRecipient = recipient;
        emit FeeRecipientUpdated(old, recipient);
    }

    function setDepositLimit(uint256 limit) external onlyOwner {
        depositLimit = limit;
        emit DepositLimitUpdated(limit);
    }

    function setRiskScore(address strategy, uint8 score) external onlyOwner {
        strategyRiskScore[strategy] = score;
        emit RiskScoreUpdated(strategy, score);
    }

    // ──────────────────────────────────────────────
    //  ERC-4626 overrides
    // ──────────────────────────────────────────────

    /**
     * @notice Total assets = idle balance in vault + deployed assets in strategies.
     */
    function totalAssets() public view override returns (uint256) {
        uint256 idle = IERC20(asset()).balanceOf(address(this));
        uint256 deployed = address(strategyManager) != address(0)
            ? strategyManager.totalDeployedAssets()
            : 0;
        return idle + deployed;
    }

    function maxDeposit(address) public view override returns (uint256) {
        if (emergencyMode || paused()) return 0;
        uint256 current = totalAssets();
        if (current >= depositLimit) return 0;
        return depositLimit - current;
    }

    function maxMint(address receiver) public view override returns (uint256) {
        uint256 maxDep = maxDeposit(receiver);
        return convertToShares(maxDep);
    }

    // ──────────────────────────────────────────────
    //  Deposit / Withdraw hooks
    // ──────────────────────────────────────────────

    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal override nonReentrant whenNotPaused {
        if (emergencyMode) revert EmergencyModeActive();
        if (assets == 0) revert ZeroAmount();
        if (assets > maxDeposit(receiver)) revert ExceedsDepositLimit();

        super._deposit(caller, receiver, assets, shares);

        // Auto-deploy idle assets to strategies
        _deployIdleAssets();
    }

    function _withdraw(
        address caller,
        address receiver,
        address ownerAddr,
        uint256 assets,
        uint256 shares
    ) internal override nonReentrant {
        if (assets == 0) revert ZeroAmount();

        // If vault doesn't hold enough idle, pull from strategies
        uint256 idle = IERC20(asset()).balanceOf(address(this));
        if (idle < assets && address(strategyManager) != address(0)) {
            uint256 deficit = assets - idle;
            uint256 actual = strategyManager.withdrawAssets(deficit);
            emit AssetsWithdrawn(deficit, actual);
        }

        super._withdraw(caller, receiver, ownerAddr, assets, shares);
    }

    // ──────────────────────────────────────────────
    //  Harvest & Compound
    // ──────────────────────────────────────────────

    /**
     * @notice Harvest profits from strategies and take performance fee.
     * @dev Restricted to vault owner or keeper to prevent flash-loan profit extraction.
     */
    function harvest() external nonReentrant whenNotPaused onlyOwner returns (uint256 profit) {
        if (address(strategyManager) == address(0)) revert NoStrategyManager();
        if (emergencyMode) revert EmergencyModeActive();

        profit = strategyManager.harvest();

        uint256 feeTaken;
        if (profit > 0 && performanceFee > 0) {
            feeTaken = (profit * performanceFee) / FEE_DENOMINATOR;
            IERC20(asset()).safeTransfer(feeRecipient, feeTaken);
        }

        lastHarvestProfit = profit;
        totalProfitAccrued += profit;

        // Update high-water mark
        uint256 currentAssets = totalAssets();
        if (currentAssets > highWaterMark) {
            highWaterMark = currentAssets;
        }

        emit Harvested(profit, feeTaken, block.timestamp);
    }

    /**
     * @notice Re-deploy idle assets into strategies (auto-compound).
     */
    function compound() external nonReentrant whenNotPaused {
        if (address(strategyManager) == address(0)) revert NoStrategyManager();
        if (emergencyMode) revert EmergencyModeActive();
        if (block.timestamp < lastCompoundTimestamp + COMPOUND_COOLDOWN) {
            revert CompoundCooldown();
        }

        uint256 deployed = _deployIdleAssets();
        lastCompoundTimestamp = block.timestamp;

        emit Compounded(deployed, block.timestamp);
    }

    /**
     * @notice Collect management fee (annualised, called periodically by keeper).
     * @dev Uses a dedicated lastFeeCollectionTimestamp independent of compound
     *      timing to prevent fee avoidance or fee spiking.
     */
    function collectManagementFee() external nonReentrant onlyOwner {
        if (managementFee == 0) return;
        if (totalSupply() == 0) return;

        // Mint shares to fee recipient proportional to AUM * fee * elapsed time
        uint256 elapsed = block.timestamp - lastFeeCollectionTimestamp;
        lastFeeCollectionTimestamp = block.timestamp;

        uint256 feeShares = (totalSupply() * managementFee * elapsed)
            / (FEE_DENOMINATOR * 365 days);

        if (feeShares > 0) {
            _mint(feeRecipient, feeShares);
        }
    }

    // ──────────────────────────────────────────────
    //  Emergency
    // ──────────────────────────────────────────────

    /**
     * @notice Activate emergency mode: pull all assets from strategies,
     *         pause deposits, allow proportional withdrawals only.
     */
    function activateEmergencyMode() external onlyOwner {
        emergencyMode = true;
        _pause();

        uint256 recovered;
        if (address(strategyManager) != address(0)) {
            recovered = strategyManager.emergencyWithdrawAll();
        }

        emit EmergencyModeActivated(msg.sender, recovered);
    }

    /**
     * @notice Deactivate emergency mode and resume normal operation.
     */
    function deactivateEmergencyMode() external onlyOwner {
        if (!emergencyMode) revert EmergencyModeNotActive();
        emergencyMode = false;
        _unpause();
        emit EmergencyModeDeactivated(msg.sender);
    }

    /**
     * @notice Emergency withdrawal — always available even when paused.
     * @dev Caps transfer to the vault's idle balance to prevent bank-run
     *      reverts when most funds are deployed in strategies. Users receive
     *      the minimum of their proportional share and the available idle balance.
     */
    function emergencyWithdraw(uint256 shares) external nonReentrant {
        if (shares == 0) revert ZeroAmount();
        uint256 assets = convertToAssets(shares);
        uint256 idle = IERC20(asset()).balanceOf(address(this));

        // Cap withdrawal to available idle balance to prevent revert
        uint256 transferAmount = assets < idle ? assets : idle;
        if (transferAmount == 0) revert InsufficientIdleBalance(assets, idle);

        // If we can only partially fill, burn proportional shares
        if (transferAmount < assets) {
            // Only burn shares proportional to what we can actually transfer
            uint256 sharesToBurn = (shares * transferAmount) / assets;
            if (sharesToBurn == 0) revert ZeroAmount();
            _burn(msg.sender, sharesToBurn);
            emit EmergencyWithdrawal(msg.sender, sharesToBurn, transferAmount);
        } else {
            _burn(msg.sender, shares);
            emit EmergencyWithdrawal(msg.sender, shares, transferAmount);
        }

        IERC20(asset()).safeTransfer(msg.sender, transferAmount);
    }

    // ──────────────────────────────────────────────
    //  Pause
    // ──────────────────────────────────────────────

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ──────────────────────────────────────────────
    //  Internal helpers
    // ──────────────────────────────────────────────

    function _deployIdleAssets() internal returns (uint256 deployed) {
        if (address(strategyManager) == address(0)) return 0;

        uint256 idle = IERC20(asset()).balanceOf(address(this));
        if (idle == 0) return 0;

        strategyManager.deployAssets(idle);
        deployed = idle;

        emit AssetsDeployed(deployed);
    }

    // ──────────────────────────────────────────────
    //  View helpers
    // ──────────────────────────────────────────────

    function idleAssets() external view returns (uint256) {
        return IERC20(asset()).balanceOf(address(this));
    }

    function deployedAssets() external view returns (uint256) {
        if (address(strategyManager) == address(0)) return 0;
        return strategyManager.totalDeployedAssets();
    }

    function pricePerShare() external view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return 10 ** decimals();
        return (totalAssets() * 10 ** decimals()) / supply;
    }
}
