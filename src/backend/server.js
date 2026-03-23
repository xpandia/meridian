/**
 * Meridian — AI-Powered DeFi Yield Optimization API
 *
 * Provides yield data aggregation, portfolio analytics, strategy
 * recommendations, historical performance, and risk metrics for
 * the Meridian vault system on HashKey Chain.
 */

const express = require("express");
const cors = require("cors");
const helmet = require("helmet");
const rateLimit = require("express-rate-limit");
const { ethers } = require("ethers");
const http = require("http");
const { WebSocketServer } = require("ws");

// ─── Config ────────────────────────────────────────────────────────────────

const PORT = process.env.PORT || 3001;
const RPC_URL = process.env.RPC_URL || "https://hashkeychain-testnet.alt.technology";
const VAULT_ADDRESS = process.env.VAULT_ADDRESS || ethers.ZeroAddress;
const STRATEGY_MANAGER_ADDRESS = process.env.STRATEGY_MANAGER_ADDRESS || ethers.ZeroAddress;
const API_KEY = process.env.MERIDIAN_API_KEY || "";
const RISK_FREE_RATE = 0.05; // 5% annualized risk-free rate for Sharpe calculation

// ─── ABIs (minimal) ───────────────────────────────────────────────────────

const VAULT_ABI = [
  "function totalAssets() view returns (uint256)",
  "function totalSupply() view returns (uint256)",
  "function pricePerShare() view returns (uint256)",
  "function idleAssets() view returns (uint256)",
  "function deployedAssets() view returns (uint256)",
  "function managementFee() view returns (uint256)",
  "function performanceFee() view returns (uint256)",
  "function highWaterMark() view returns (uint256)",
  "function totalProfitAccrued() view returns (uint256)",
  "function lastHarvestProfit() view returns (uint256)",
  "function emergencyMode() view returns (bool)",
  "function depositLimit() view returns (uint256)",
  "function balanceOf(address) view returns (uint256)",
  "function convertToAssets(uint256) view returns (uint256)",
  "function maxDeposit(address) view returns (uint256)",
  "event Harvested(uint256 profit, uint256 performanceFeeTaken, uint256 timestamp)",
  "event Compounded(uint256 amountRedeployed, uint256 timestamp)",
  "event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares)",
  "event Withdraw(address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares)",
];

const STRATEGY_MANAGER_ABI = [
  "function strategyCount() view returns (uint256)",
  "function activeStrategyCount() view returns (uint256)",
  "function totalDeployedAssets() view returns (uint256)",
  "function needsRebalance() view returns (bool)",
  "function getStrategy(uint256) view returns (tuple(address addr, uint256 weight, uint8 riskScore, bool active, uint256 totalDeposited, uint256 totalProfit, uint256 lastHarvest))",
  "function getAllStrategies() view returns (tuple(address addr, uint256 weight, uint8 riskScore, bool active, uint256 totalDeposited, uint256 totalProfit, uint256 lastHarvest)[])",
];

// ─── Provider & Contracts ─────────────────────────────────────────────────

let provider, vaultContract, strategyManagerContract;

function initContracts() {
  provider = new ethers.JsonRpcProvider(RPC_URL);
  if (VAULT_ADDRESS !== ethers.ZeroAddress) {
    vaultContract = new ethers.Contract(VAULT_ADDRESS, VAULT_ABI, provider);
  }
  if (STRATEGY_MANAGER_ADDRESS !== ethers.ZeroAddress) {
    strategyManagerContract = new ethers.Contract(
      STRATEGY_MANAGER_ADDRESS,
      STRATEGY_MANAGER_ABI,
      provider
    );
  }
}

// ─── In-memory caches / simulated historical data ─────────────────────────

const historicalSnapshots = [];
const MAX_SNAPSHOTS = 1000;

function recordSnapshot(data) {
  historicalSnapshots.push({ ...data, timestamp: Date.now() });
  if (historicalSnapshots.length > MAX_SNAPSHOTS) historicalSnapshots.shift();
}

// ─── Risk calculation helpers ─────────────────────────────────────────────

/**
 * Compute portfolio-level risk metrics from strategy data.
 */
function computeRiskMetrics(strategies) {
  if (!strategies || strategies.length === 0) {
    return {
      portfolioRiskScore: 0,
      diversificationIndex: 0,
      maxDrawdownEstimate: 0,
      sharpeEstimate: 0,
      concentrationRisk: "N/A",
    };
  }

  const active = strategies.filter((s) => s.active);
  if (active.length === 0) {
    return {
      portfolioRiskScore: 0,
      diversificationIndex: 0,
      maxDrawdownEstimate: 0,
      sharpeEstimate: 0,
      concentrationRisk: "N/A",
    };
  }

  // Weighted risk score
  const totalWeight = active.reduce((sum, s) => sum + Number(s.weight), 0);
  const weightedRisk =
    active.reduce((sum, s) => sum + Number(s.riskScore) * Number(s.weight), 0) /
    (totalWeight || 1);

  // Herfindahl-Hirschman Index for concentration
  const hhi = active.reduce((sum, s) => {
    const pct = Number(s.weight) / (totalWeight || 1);
    return sum + pct * pct;
  }, 0);

  const diversification = 1 - hhi; // 0 = single strategy, ~1 = well diversified

  let concentrationRisk = "Low";
  if (hhi > 0.5) concentrationRisk = "High";
  else if (hhi > 0.25) concentrationRisk = "Medium";

  // Estimated max drawdown from risk scores (heuristic)
  const maxRisk = Math.max(...active.map((s) => Number(s.riskScore)));
  const maxDrawdownEstimate = (maxRisk / 100) * 30; // worst strategy could lose up to 30%

  // Sharpe ratio: (mean return - risk-free rate) / stddev of returns
  const totalDeposited = active.reduce((sum, s) => sum + Number(s.totalDeposited || 0), 0);
  const returns = active
    .filter((s) => Number(s.totalDeposited || 0) > 0)
    .map((s) => Number(s.totalProfit || 0) / Number(s.totalDeposited));
  let sharpeEstimate = 0;
  if (returns.length > 1) {
    const meanReturn = returns.reduce((a, b) => a + b, 0) / returns.length;
    const variance = returns.reduce((sum, r) => sum + (r - meanReturn) ** 2, 0) / (returns.length - 1);
    const stddev = Math.sqrt(variance);
    sharpeEstimate = stddev > 0 ? (meanReturn - RISK_FREE_RATE) / stddev : 0;
  } else if (returns.length === 1) {
    // Single strategy: cannot compute variance, report excess return only
    sharpeEstimate = returns[0] - RISK_FREE_RATE;
  }

  return {
    portfolioRiskScore: Math.round(weightedRisk),
    diversificationIndex: Math.round(diversification * 100) / 100,
    maxDrawdownEstimate: Math.round(maxDrawdownEstimate * 100) / 100,
    sharpeEstimate: Math.round(sharpeEstimate * 100) / 100,
    concentrationRisk,
  };
}

/**
 * AI-style strategy recommendation engine.
 * Considers risk scores, current APY estimates, and weights.
 */
function generateRecommendations(strategies, riskTolerance = "moderate") {
  const riskThresholds = {
    conservative: 30,
    moderate: 60,
    aggressive: 90,
  };
  const threshold = riskThresholds[riskTolerance] || 60;
  const active = (strategies || []).filter((s) => s.active);

  const recommendations = [];

  // Check if rebalance is needed based on profit distribution
  const totalProfit = active.reduce((s, st) => s + Number(st.totalProfit || 0), 0);
  const totalDeposited = active.reduce((s, st) => s + Number(st.totalDeposited || 0), 0);

  // Per-strategy recommendations
  for (const strat of active) {
    const risk = Number(strat.riskScore);
    const weight = Number(strat.weight);
    const profit = Number(strat.totalProfit || 0);
    const deposited = Number(strat.totalDeposited || 0);
    const roi = deposited > 0 ? (profit / deposited) * 100 : 0;

    if (risk > threshold && weight > 1500) {
      recommendations.push({
        strategy: strat.addr,
        action: "REDUCE_WEIGHT",
        reason: `Risk score ${risk} exceeds your ${riskTolerance} threshold (${threshold}). Currently over-allocated at ${weight / 100}%.`,
        urgency: "high",
      });
    }

    if (risk <= threshold && roi > 5 && weight < 3000) {
      recommendations.push({
        strategy: strat.addr,
        action: "INCREASE_WEIGHT",
        reason: `Strong ROI of ${roi.toFixed(2)}% with acceptable risk (${risk}). Consider increasing allocation.`,
        urgency: "medium",
      });
    }

    if (roi < 0) {
      recommendations.push({
        strategy: strat.addr,
        action: "REVIEW",
        reason: `Negative ROI of ${roi.toFixed(2)}%. Investigate strategy health.`,
        urgency: "high",
      });
    }
  }

  // Portfolio-wide recommendations
  if (active.length < 3) {
    recommendations.push({
      strategy: null,
      action: "DIVERSIFY",
      reason: "Portfolio has fewer than 3 active strategies. Consider adding more for diversification.",
      urgency: "medium",
    });
  }

  if (active.length > 0) {
    const maxWeight = Math.max(...active.map((s) => Number(s.weight)));
    if (maxWeight > 5000) {
      recommendations.push({
        strategy: null,
        action: "REBALANCE",
        reason: `A single strategy holds over ${maxWeight / 100}% of allocation. High concentration risk.`,
        urgency: "high",
      });
    }
  }

  return recommendations;
}

// ─── Express app ──────────────────────────────────────────────────────────

const app = express();

app.use(helmet());
app.use(cors());
app.use(express.json());

const limiter = rateLimit({
  windowMs: 60 * 1000,
  max: 120,
  standardHeaders: true,
  legacyHeaders: false,
});
app.use(limiter);

// ─── Middleware: API key authentication ───────────────────────────────────

function requireAuth(req, res, next) {
  // If no API_KEY is set, skip auth (development mode)
  if (!API_KEY) return next();

  const token =
    req.headers["x-api-key"] ||
    req.headers.authorization?.replace("Bearer ", "");

  if (!token || token !== API_KEY) {
    return res.status(401).json({ error: "Unauthorized. Provide a valid API key via x-api-key header or Bearer token." });
  }
  next();
}

// Apply auth to all /api routes except health
app.use("/api", (req, res, next) => {
  if (req.path === "/health") return next();
  requireAuth(req, res, next);
});

// ─── Middleware: contracts guard ──────────────────────────────────────────

function requireContracts(req, res, next) {
  if (!vaultContract || !strategyManagerContract) {
    return res.status(503).json({
      error: "Contracts not configured. Set VAULT_ADDRESS and STRATEGY_MANAGER_ADDRESS.",
    });
  }
  next();
}

// ─── Routes ──────────────────────────────────────────────────────────────

// Health
app.get("/api/health", (_req, res) => {
  res.json({
    status: "ok",
    chain: "HashKey Chain",
    rpc: RPC_URL,
    vaultConfigured: !!vaultContract,
    strategyManagerConfigured: !!strategyManagerContract,
    uptime: process.uptime(),
  });
});

// ──── Vault overview ─────────────────────────────────────────────────────

app.get("/api/vault", requireContracts, async (_req, res) => {
  try {
    const [
      totalAssets,
      totalSupply,
      pricePerShare,
      idle,
      deployed,
      mgmtFee,
      perfFee,
      hwm,
      totalProfit,
      lastProfit,
      emergency,
      depLimit,
    ] = await Promise.all([
      vaultContract.totalAssets(),
      vaultContract.totalSupply(),
      vaultContract.pricePerShare(),
      vaultContract.idleAssets(),
      vaultContract.deployedAssets(),
      vaultContract.managementFee(),
      vaultContract.performanceFee(),
      vaultContract.highWaterMark(),
      vaultContract.totalProfitAccrued(),
      vaultContract.lastHarvestProfit(),
      vaultContract.emergencyMode(),
      vaultContract.depositLimit(),
    ]);

    const data = {
      totalAssets: totalAssets.toString(),
      totalSupply: totalSupply.toString(),
      pricePerShare: pricePerShare.toString(),
      idleAssets: idle.toString(),
      deployedAssets: deployed.toString(),
      managementFeeBps: Number(mgmtFee),
      performanceFeeBps: Number(perfFee),
      highWaterMark: hwm.toString(),
      totalProfitAccrued: totalProfit.toString(),
      lastHarvestProfit: lastProfit.toString(),
      emergencyMode: emergency,
      depositLimit: depLimit.toString(),
    };

    recordSnapshot(data);
    res.json(data);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ──── Yield data aggregation ─────────────────────────────────────────────

app.get("/api/yield", requireContracts, async (_req, res) => {
  try {
    const [totalAssets, totalProfit, strategies] = await Promise.all([
      vaultContract.totalAssets(),
      vaultContract.totalProfitAccrued(),
      strategyManagerContract.getAllStrategies(),
    ]);

    const strategyYields = strategies
      .filter((s) => s.active)
      .map((s) => {
        const deposited = Number(ethers.formatEther(s.totalDeposited));
        const profit = Number(ethers.formatEther(s.totalProfit));
        const roi = deposited > 0 ? (profit / deposited) * 100 : 0;

        return {
          address: s.addr,
          weight: Number(s.weight) / 100,
          riskScore: Number(s.riskScore),
          deposited: s.totalDeposited.toString(),
          profit: s.totalProfit.toString(),
          roiPercent: Math.round(roi * 100) / 100,
          lastHarvest: Number(s.lastHarvest),
        };
      });

    res.json({
      totalAssets: totalAssets.toString(),
      totalProfit: totalProfit.toString(),
      overallROI:
        Number(ethers.formatEther(totalAssets)) > 0
          ? Math.round(
              (Number(ethers.formatEther(totalProfit)) /
                Number(ethers.formatEther(totalAssets))) *
                10000
            ) / 100
          : 0,
      strategies: strategyYields,
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ──── Portfolio analytics ────────────────────────────────────────────────

app.get("/api/portfolio/:address", requireContracts, async (req, res) => {
  try {
    const userAddress = req.params.address;
    if (!ethers.isAddress(userAddress)) {
      return res.status(400).json({ error: "Invalid Ethereum address" });
    }

    const [shares, pricePerShare, totalAssets, totalSupply] = await Promise.all([
      vaultContract.balanceOf(userAddress),
      vaultContract.pricePerShare(),
      vaultContract.totalAssets(),
      vaultContract.totalSupply(),
    ]);

    const userAssets =
      Number(totalSupply) > 0
        ? (BigInt(shares) * BigInt(totalAssets)) / BigInt(totalSupply)
        : 0n;

    const portfolioShare =
      Number(totalSupply) > 0
        ? (Number(shares) / Number(totalSupply)) * 100
        : 0;

    res.json({
      user: userAddress,
      shares: shares.toString(),
      estimatedAssets: userAssets.toString(),
      pricePerShare: pricePerShare.toString(),
      portfolioSharePercent: Math.round(portfolioShare * 100) / 100,
      maxDeposit: (await vaultContract.maxDeposit(userAddress)).toString(),
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ──── Strategy recommendation engine ─────────────────────────────────────

app.get("/api/recommendations", requireContracts, async (req, res) => {
  try {
    const riskTolerance = req.query.risk || "moderate";
    const strategies = await strategyManagerContract.getAllStrategies();

    const parsed = strategies.map((s) => ({
      addr: s.addr,
      weight: Number(s.weight),
      riskScore: Number(s.riskScore),
      active: s.active,
      totalDeposited: Number(ethers.formatEther(s.totalDeposited)),
      totalProfit: Number(ethers.formatEther(s.totalProfit)),
      lastHarvest: Number(s.lastHarvest),
    }));

    const recommendations = generateRecommendations(parsed, riskTolerance);
    const needsRebalance = await strategyManagerContract.needsRebalance();

    res.json({
      riskTolerance,
      needsRebalance,
      recommendations,
      analysisTimestamp: Date.now(),
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ──── Strategies detail ──────────────────────────────────────────────────

app.get("/api/strategies", requireContracts, async (_req, res) => {
  try {
    const [strategies, needsRebalance, totalDeployed, activeCount] =
      await Promise.all([
        strategyManagerContract.getAllStrategies(),
        strategyManagerContract.needsRebalance(),
        strategyManagerContract.totalDeployedAssets(),
        strategyManagerContract.activeStrategyCount(),
      ]);

    const formatted = strategies.map((s, i) => ({
      index: i,
      address: s.addr,
      weightPercent: Number(s.weight) / 100,
      riskScore: Number(s.riskScore),
      active: s.active,
      totalDeposited: s.totalDeposited.toString(),
      totalProfit: s.totalProfit.toString(),
      lastHarvest: new Date(Number(s.lastHarvest) * 1000).toISOString(),
    }));

    res.json({
      totalStrategies: strategies.length,
      activeStrategies: Number(activeCount),
      totalDeployedAssets: totalDeployed.toString(),
      needsRebalance,
      strategies: formatted,
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ──── Risk metrics ───────────────────────────────────────────────────────

app.get("/api/risk", requireContracts, async (_req, res) => {
  try {
    const strategies = await strategyManagerContract.getAllStrategies();

    const parsed = strategies.map((s) => ({
      addr: s.addr,
      weight: Number(s.weight),
      riskScore: Number(s.riskScore),
      active: s.active,
      totalDeposited: Number(ethers.formatEther(s.totalDeposited)),
      totalProfit: Number(ethers.formatEther(s.totalProfit)),
    }));

    const metrics = computeRiskMetrics(parsed);

    res.json({
      ...metrics,
      strategyCount: strategies.length,
      activeCount: parsed.filter((s) => s.active).length,
      timestamp: Date.now(),
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ──── Historical performance ─────────────────────────────────────────────

app.get("/api/history", (_req, res) => {
  const limit = Math.min(parseInt(_req.query.limit) || 100, MAX_SNAPSHOTS);
  const from = parseInt(_req.query.from) || 0;

  const filtered = from
    ? historicalSnapshots.filter((s) => s.timestamp >= from)
    : historicalSnapshots;

  res.json({
    count: filtered.length,
    snapshots: filtered.slice(-limit),
  });
});

// ──── Harvest history (on-chain events) ──────────────────────────────────

app.get("/api/harvests", requireContracts, async (req, res) => {
  try {
    const blocks = parseInt(req.query.blocks) || 5000;
    const currentBlock = await provider.getBlockNumber();
    const fromBlock = Math.max(currentBlock - blocks, 0);

    const filter = vaultContract.filters.Harvested();
    const events = await vaultContract.queryFilter(filter, fromBlock, currentBlock);

    const harvests = events.map((e) => ({
      profit: e.args[0].toString(),
      performanceFee: e.args[1].toString(),
      timestamp: Number(e.args[2]),
      blockNumber: e.blockNumber,
      txHash: e.transactionHash,
    }));

    res.json({
      fromBlock,
      toBlock: currentBlock,
      count: harvests.length,
      harvests,
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ─── Error handler ───────────────────────────────────────────────────────

app.use((err, _req, res, _next) => {
  console.error("[Meridian API Error]", err);
  res.status(500).json({ error: "Internal server error" });
});

// ─── WebSocket support for real-time updates ─────────────────────────────

const server = http.createServer(app);
const wss = new WebSocketServer({ server, path: "/ws" });

const WS_BROADCAST_INTERVAL = 15_000; // 15 seconds

wss.on("connection", (ws) => {
  console.log("[WS] Client connected");
  ws.isAlive = true;
  ws.on("pong", () => { ws.isAlive = true; });
  ws.on("close", () => { console.log("[WS] Client disconnected"); });
});

// Heartbeat: terminate dead connections
const heartbeat = setInterval(() => {
  wss.clients.forEach((ws) => {
    if (!ws.isAlive) return ws.terminate();
    ws.isAlive = false;
    ws.ping();
  });
}, 30_000);

wss.on("close", () => clearInterval(heartbeat));

// Broadcast vault data to all connected clients periodically
async function broadcastVaultData() {
  if (!vaultContract || !strategyManagerContract) return;
  if (wss.clients.size === 0) return;

  try {
    const [totalAssets, pricePerShare, idle, deployed, emergency] =
      await Promise.all([
        vaultContract.totalAssets(),
        vaultContract.pricePerShare(),
        vaultContract.idleAssets(),
        vaultContract.deployedAssets(),
        vaultContract.emergencyMode(),
      ]);

    const payload = JSON.stringify({
      type: "vault_update",
      data: {
        totalAssets: totalAssets.toString(),
        pricePerShare: pricePerShare.toString(),
        idleAssets: idle.toString(),
        deployedAssets: deployed.toString(),
        emergencyMode: emergency,
        timestamp: Date.now(),
      },
    });

    wss.clients.forEach((ws) => {
      if (ws.readyState === ws.OPEN) ws.send(payload);
    });
  } catch (err) {
    console.error("[WS Broadcast Error]", err.message);
  }
}

let broadcastTimer;

// ─── Start ───────────────────────────────────────────────────────────────

initContracts();

server.listen(PORT, () => {
  console.log(`Meridian API running on port ${PORT}`);
  console.log(`  Chain RPC : ${RPC_URL}`);
  console.log(`  Vault     : ${VAULT_ADDRESS}`);
  console.log(`  StratMgr  : ${STRATEGY_MANAGER_ADDRESS}`);
  console.log(`  WebSocket : ws://localhost:${PORT}/ws`);
  console.log(`  Auth      : ${API_KEY ? "enabled" : "disabled (set MERIDIAN_API_KEY to enable)"}`);

  broadcastTimer = setInterval(broadcastVaultData, WS_BROADCAST_INTERVAL);
});

// Graceful shutdown
function shutdown() {
  console.log("[Meridian] Shutting down...");
  clearInterval(broadcastTimer);
  clearInterval(heartbeat);
  wss.close();
  server.close(() => process.exit(0));
}
process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);

module.exports = app;
