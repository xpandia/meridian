// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title IStrategy
 * @notice Interface every yield strategy must implement.
 */
interface IStrategy {
    function deposit(uint256 amount) external;
    function withdraw(uint256 amount) external returns (uint256 actual);
    function harvest() external returns (uint256 profit);
    function balanceDeployed() external view returns (uint256);
    function estimatedAPY() external view returns (uint256); // basis points
    function emergencyWithdraw() external returns (uint256 recovered);
}

/**
 * @title StrategyManager
 * @notice Orchestrates multiple yield strategies: registration, weighting,
 *         rebalancing, harvest, compound, and slippage protection.
 * @dev Called by MeridianVault to deploy / withdraw / harvest assets.
 */
contract StrategyManager is Ownable2Step, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    // ──────────────────────────────────────────────
    //  Types
    // ──────────────────────────────────────────────

    struct StrategyInfo {
        address addr;
        uint256 weight;          // target allocation in basis points (sum = 10_000)
        uint8   riskScore;       // 1-100, set by AI off-chain
        bool    active;
        uint256 totalDeposited;
        uint256 totalProfit;
        uint256 lastHarvest;
    }

    // ──────────────────────────────────────────────
    //  Constants
    // ──────────────────────────────────────────────

    uint256 public constant WEIGHT_DENOMINATOR = 10_000;
    uint256 public constant MAX_STRATEGIES = 20;
    uint256 public constant MAX_SLIPPAGE = 500;            // 5 % default max
    uint256 public constant REBALANCE_THRESHOLD = 200;     // 2 % drift triggers rebalance

    // ──────────────────────────────────────────────
    //  State
    // ──────────────────────────────────────────────

    IERC20 public immutable asset;
    address public vault;          // only the vault may call mutative methods

    StrategyInfo[] public strategies;
    mapping(address => uint256) public strategyIndex; // addr -> index+1 (0 = not registered)

    uint256 public slippageTolerance; // basis points

    // ──────────────────────────────────────────────
    //  Events
    // ──────────────────────────────────────────────

    event StrategyAdded(address indexed strategy, uint256 weight, uint8 riskScore);
    event StrategyRemoved(address indexed strategy);
    event StrategyWeightsUpdated(uint256[] newWeights);
    event StrategyRiskScoreUpdated(address indexed strategy, uint8 newScore);
    event Rebalanced(uint256 timestamp);
    event Harvested(address indexed strategy, uint256 profit);
    event HarvestAll(uint256 totalProfit);
    event AssetsDeployed(uint256 total);
    event AssetsWithdrawn(uint256 requested, uint256 actual);
    event EmergencyWithdrawAll(uint256 totalRecovered);
    event SlippageToleranceUpdated(uint256 newTolerance);
    event VaultUpdated(address indexed oldVault, address indexed newVault);

    // ──────────────────────────────────────────────
    //  Errors
    // ──────────────────────────────────────────────

    error OnlyVault();
    error StrategyAlreadyRegistered();
    error StrategyNotFound();
    error TooManyStrategies();
    error InvalidWeights();
    error SlippageExceeded(uint256 expected, uint256 actual);
    error InvalidAddress();
    error InvalidSlippage();

    // ──────────────────────────────────────────────
    //  Modifiers
    // ──────────────────────────────────────────────

    modifier onlyVault() {
        if (msg.sender != vault) revert OnlyVault();
        _;
    }

    // ──────────────────────────────────────────────
    //  Constructor
    // ──────────────────────────────────────────────

    constructor(IERC20 asset_, address vault_) Ownable(msg.sender) {
        if (address(asset_) == address(0) || vault_ == address(0)) revert InvalidAddress();
        asset = asset_;
        vault = vault_;
        slippageTolerance = 100; // 1 % default
    }

    // ──────────────────────────────────────────────
    //  Admin — Strategy lifecycle
    // ──────────────────────────────────────────────

    function addStrategy(
        address strategy,
        uint256 weight,
        uint8 riskScore
    ) external onlyOwner {
        if (strategy == address(0)) revert InvalidAddress();
        if (strategyIndex[strategy] != 0) revert StrategyAlreadyRegistered();
        if (strategies.length >= MAX_STRATEGIES) revert TooManyStrategies();

        strategies.push(StrategyInfo({
            addr: strategy,
            weight: weight,
            riskScore: riskScore,
            active: true,
            totalDeposited: 0,
            totalProfit: 0,
            lastHarvest: block.timestamp
        }));
        strategyIndex[strategy] = strategies.length; // 1-indexed

        // Approve strategy to pull tokens
        asset.forceApprove(strategy, type(uint256).max);

        emit StrategyAdded(strategy, weight, riskScore);
    }

    function removeStrategy(address strategy) external onlyOwner {
        uint256 idx = _getIndex(strategy);
        StrategyInfo storage info = strategies[idx];

        // Withdraw everything from the strategy first
        if (info.totalDeposited > 0) {
            IStrategy(info.addr).emergencyWithdraw();
        }

        info.active = false;
        asset.forceApprove(strategy, 0);

        emit StrategyRemoved(strategy);
    }

    /**
     * @notice Update weights for all active strategies. Must sum to WEIGHT_DENOMINATOR.
     * @param newWeights Array of weights in the same order as `strategies`.
     */
    function updateWeights(uint256[] calldata newWeights) external onlyOwner {
        if (newWeights.length != strategies.length) revert InvalidWeights();

        uint256 totalWeight;
        for (uint256 i; i < newWeights.length; ++i) {
            strategies[i].weight = newWeights[i];
            if (strategies[i].active) {
                totalWeight += newWeights[i];
            }
        }
        if (totalWeight != WEIGHT_DENOMINATOR) revert InvalidWeights();

        emit StrategyWeightsUpdated(newWeights);
    }

    function updateRiskScore(address strategy, uint8 score) external onlyOwner {
        uint256 idx = _getIndex(strategy);
        strategies[idx].riskScore = score;
        emit StrategyRiskScoreUpdated(strategy, score);
    }

    function setSlippageTolerance(uint256 bps) external onlyOwner {
        if (bps > MAX_SLIPPAGE) revert InvalidSlippage();
        slippageTolerance = bps;
        emit SlippageToleranceUpdated(bps);
    }

    function setVault(address vault_) external onlyOwner {
        if (vault_ == address(0)) revert InvalidAddress();
        address old = vault;
        vault = vault_;
        emit VaultUpdated(old, vault_);
    }

    // ──────────────────────────────────────────────
    //  Vault-callable — Deploy / Withdraw / Harvest
    // ──────────────────────────────────────────────

    /**
     * @notice Deploy assets across strategies according to weights.
     */
    function deployAssets(uint256 amount) external onlyVault nonReentrant whenNotPaused {
        asset.safeTransferFrom(vault, address(this), amount);

        uint256 remaining = amount;
        uint256 len = strategies.length;

        for (uint256 i; i < len; ++i) {
            StrategyInfo storage info = strategies[i];
            if (!info.active || info.weight == 0) continue;

            uint256 share = (amount * info.weight) / WEIGHT_DENOMINATOR;
            if (share > remaining) share = remaining;
            if (share == 0) continue;

            asset.safeTransfer(info.addr, share);
            IStrategy(info.addr).deposit(share);

            info.totalDeposited += share;
            remaining -= share;
        }

        // Dust goes to first active strategy
        if (remaining > 0) {
            for (uint256 i; i < len; ++i) {
                if (strategies[i].active) {
                    asset.safeTransfer(strategies[i].addr, remaining);
                    IStrategy(strategies[i].addr).deposit(remaining);
                    strategies[i].totalDeposited += remaining;
                    break;
                }
            }
        }

        emit AssetsDeployed(amount);
    }

    /**
     * @notice Withdraw requested amount, pulling proportionally from strategies.
     *         Applies slippage protection.
     */
    function withdrawAssets(uint256 amount) external onlyVault nonReentrant returns (uint256 totalWithdrawn) {
        uint256 remaining = amount;
        uint256 len = strategies.length;

        for (uint256 i; i < len && remaining > 0; ++i) {
            StrategyInfo storage info = strategies[i];
            if (!info.active) continue;

            uint256 deployed = IStrategy(info.addr).balanceDeployed();
            if (deployed == 0) continue;

            // Proportional withdrawal
            uint256 pull = remaining.min(deployed);
            uint256 actual = IStrategy(info.addr).withdraw(pull);

            if (actual < pull) {
                // Check slippage
                uint256 slippage = ((pull - actual) * WEIGHT_DENOMINATOR) / pull;
                if (slippage > slippageTolerance) {
                    revert SlippageExceeded(pull, actual);
                }
            }

            info.totalDeposited = info.totalDeposited > actual ? info.totalDeposited - actual : 0;
            totalWithdrawn += actual;
            remaining -= actual.min(remaining);
        }

        // Transfer withdrawn assets back to vault
        if (totalWithdrawn > 0) {
            asset.safeTransfer(vault, totalWithdrawn);
        }

        emit AssetsWithdrawn(amount, totalWithdrawn);
    }

    /**
     * @notice Harvest profits from all active strategies.
     */
    function harvest() external onlyVault nonReentrant returns (uint256 totalProfit) {
        uint256 len = strategies.length;

        for (uint256 i; i < len; ++i) {
            StrategyInfo storage info = strategies[i];
            if (!info.active) continue;

            uint256 profit = IStrategy(info.addr).harvest();
            if (profit > 0) {
                info.totalProfit += profit;
                totalProfit += profit;
                emit Harvested(info.addr, profit);
            }
            info.lastHarvest = block.timestamp;
        }

        // Transfer harvested profits to vault
        if (totalProfit > 0) {
            asset.safeTransfer(vault, totalProfit);
        }

        emit HarvestAll(totalProfit);
    }

    /**
     * @notice Emergency: withdraw everything from every strategy.
     */
    function emergencyWithdrawAll() external onlyVault nonReentrant returns (uint256 totalRecovered) {
        uint256 len = strategies.length;

        for (uint256 i; i < len; ++i) {
            StrategyInfo storage info = strategies[i];
            if (!info.active) continue;

            uint256 recovered = IStrategy(info.addr).emergencyWithdraw();
            totalRecovered += recovered;
            info.totalDeposited = 0;
            info.active = false;
        }

        // Transfer everything back to vault
        uint256 bal = asset.balanceOf(address(this));
        if (bal > 0) {
            asset.safeTransfer(vault, bal);
        }

        emit EmergencyWithdrawAll(totalRecovered);
    }

    // ──────────────────────────────────────────────
    //  Rebalancing
    // ──────────────────────────────────────────────

    /**
     * @notice Rebalance strategies toward their target weights.
     *         Callable by owner (keeper / AI agent).
     */
    function rebalance() external onlyOwner nonReentrant whenNotPaused {
        uint256 total = totalDeployedAssets();
        if (total == 0) return;

        uint256 len = strategies.length;

        // First pass: withdraw from over-weight strategies
        for (uint256 i; i < len; ++i) {
            StrategyInfo storage info = strategies[i];
            if (!info.active) continue;

            uint256 target = (total * info.weight) / WEIGHT_DENOMINATOR;
            uint256 current = IStrategy(info.addr).balanceDeployed();

            if (current > target) {
                uint256 excess = current - target;
                uint256 actual = IStrategy(info.addr).withdraw(excess);
                info.totalDeposited = info.totalDeposited > actual ? info.totalDeposited - actual : 0;
            }
        }

        // Second pass: deposit into under-weight strategies
        uint256 available = asset.balanceOf(address(this));
        for (uint256 i; i < len && available > 0; ++i) {
            StrategyInfo storage info = strategies[i];
            if (!info.active) continue;

            uint256 target = (total * info.weight) / WEIGHT_DENOMINATOR;
            uint256 current = IStrategy(info.addr).balanceDeployed();

            if (current < target) {
                uint256 deficit = target - current;
                uint256 toDeposit = deficit.min(available);

                asset.safeTransfer(info.addr, toDeposit);
                IStrategy(info.addr).deposit(toDeposit);

                info.totalDeposited += toDeposit;
                available -= toDeposit;
            }
        }

        emit Rebalanced(block.timestamp);
    }

    /**
     * @notice Check if any strategy has drifted beyond the rebalance threshold.
     */
    function needsRebalance() external view returns (bool) {
        uint256 total = totalDeployedAssets();
        if (total == 0) return false;

        uint256 len = strategies.length;
        for (uint256 i; i < len; ++i) {
            StrategyInfo storage info = strategies[i];
            if (!info.active) continue;

            uint256 target = (total * info.weight) / WEIGHT_DENOMINATOR;
            uint256 current = IStrategy(info.addr).balanceDeployed();

            uint256 drift;
            if (current > target) {
                drift = ((current - target) * WEIGHT_DENOMINATOR) / total;
            } else {
                drift = ((target - current) * WEIGHT_DENOMINATOR) / total;
            }

            if (drift > REBALANCE_THRESHOLD) return true;
        }

        return false;
    }

    // ──────────────────────────────────────────────
    //  Views
    // ──────────────────────────────────────────────

    function totalDeployedAssets() public view returns (uint256 total) {
        uint256 len = strategies.length;
        for (uint256 i; i < len; ++i) {
            if (strategies[i].active) {
                total += IStrategy(strategies[i].addr).balanceDeployed();
            }
        }
    }

    function strategyCount() external view returns (uint256) {
        return strategies.length;
    }

    function activeStrategyCount() external view returns (uint256 count) {
        for (uint256 i; i < strategies.length; ++i) {
            if (strategies[i].active) count++;
        }
    }

    function getStrategy(uint256 idx) external view returns (StrategyInfo memory) {
        return strategies[idx];
    }

    function getAllStrategies() external view returns (StrategyInfo[] memory) {
        return strategies;
    }

    // ──────────────────────────────────────────────
    //  Pause
    // ──────────────────────────────────────────────

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    // ──────────────────────────────────────────────
    //  Internal
    // ──────────────────────────────────────────────

    function _getIndex(address strategy) internal view returns (uint256) {
        uint256 raw = strategyIndex[strategy];
        if (raw == 0) revert StrategyNotFound();
        return raw - 1;
    }
}
