# Meridian -- HashKey Horizon Hackathon Submission

**Tracks:** DeFi, AI
**Deadline:** April 15, 2026
**Platform:** DoraHacks BUIDL
**Repo:** https://github.com/xpandia/meridian

---

## Project Name

Meridian

## Tagline

Institutional-grade DeFi yield optimization, for everyone.

## One-Liner

Meridian is an AI-powered vault protocol on HashKey Chain that continuously analyzes, scores, and rebalances DeFi positions across multiple strategies to maximize risk-adjusted yield -- turning a single deposit into an optimized portfolio.

---

## Problem Statement

DeFi yields are fragmented across dozens of protocols, chains, and strategies. Retail users face three brutal realities:

1. **Information asymmetry** -- Institutions run quantitative models to find alpha. Retail users guess.
2. **Capital inefficiency** -- Funds sit idle in single pools while better opportunities emerge every block.
3. **Risk blindness** -- Most users cannot assess smart contract risk, impermanent loss exposure, or protocol solvency.

The result: retail leaves 40-60% of potential yield on the table.

## Solution

Meridian is a rule-based yield optimizer deployed on HashKey Chain. It continuously analyzes on-chain data, scores risk-adjusted returns, and automatically rebalances user positions across the highest-performing DeFi strategies -- all within a single ERC-4626 vault interface.

**One deposit. Maximum yield. Institutional intelligence.**

### How It Works

1. **Deposit** -- User deposits assets into a Meridian Vault on HashKey Chain.
2. **Optimize** -- The AI recommendation engine scores every available strategy by risk-adjusted return, then allocates capital across the optimal set.
3. **Earn** -- The vault auto-compounds and rebalances. Users withdraw anytime.

---

## Track Fit

### DeFi Track
- ERC-4626 compliant vault architecture on HashKey Chain
- Multi-strategy yield optimization with automatic rebalancing
- On-chain escrow, fee management, and harvest logic
- Smart contract security: ReentrancyGuard, Pausable, emergency mode, fee caps, SafeERC20

### AI Track
- AI-powered recommendation engine that scores risk-adjusted returns across all available strategies
- Real-time on-chain data analysis for strategy selection
- Automated capital allocation decisions based on quantitative risk models
- WebSocket-based real-time yield monitoring and alerting

---

## Architecture

```
User (Browser / Wallet)
        |
        v
Landing Page (Static HTML/CSS/JS)
        |
        v
Express.js API (REST + WebSocket real-time data)
        |
        v
Solidity Smart Contracts (HashKey Chain EVM)
  - MeridianVault.sol (ERC-4626 vault, deposits, withdrawals, emergency mode)
  - StrategyManager.sol (multi-strategy allocation, rebalancing, harvest)
```

## Tech Stack

| Layer        | Technology                                |
|--------------|-------------------------------------------|
| Chain        | HashKey Chain (EVM-compatible)             |
| Contracts    | Solidity 0.8.x, OpenZeppelin              |
| Backend      | Node.js, Express, ethers.js, WebSocket    |
| Frontend     | Static HTML/CSS/JS landing page           |

---

## Smart Contract Security

- ERC-4626 compliance via OpenZeppelin base
- Ownable2Step -- two-step ownership transfer
- ReentrancyGuard on all state-changing functions
- Pausable + Emergency Mode -- dual circuit breaker
- Access-controlled harvest (onlyOwner)
- Slippage protection on strategy withdrawals
- Fee caps: 5% max management fee, 30% max performance fee
- SafeERC20 -- no raw transfer calls

---

## Team

| Role                     | Responsibility                                |
|--------------------------|-----------------------------------------------|
| Smart Contract Engineer  | Vault architecture, strategy routing, security |
| Frontend Engineer        | Dashboard, portfolio visualization, wallet UX  |
| Backend Engineer         | API, risk metrics, recommendation engine       |
| Product / Design         | User experience, hackathon narrative, demo flow |

---

## Demo Video Script (3 minutes)

### [0:00 - 0:20] Hook
"DeFi yields are everywhere -- but finding the best one is like searching for a needle in a haystack. What if your deposits could find the best yields automatically? Meet Meridian."

### [0:20 - 0:50] Problem
Show a split screen: on one side, a user manually checking 5+ DeFi protocols for yields. On the other, a chart showing how yields shift every hour. Narrate the pain: "Retail users leave 40 to 60 percent of yield on the table because they can't monitor, analyze, and rebalance fast enough."

### [0:50 - 1:30] Solution Demo
Walk through the Meridian interface:
1. Connect wallet to HashKey Chain
2. Show the vault dashboard with current APY, TVL, and strategy breakdown
3. Deposit tokens into the vault -- show the transaction on HashKey Chain
4. Show the AI recommendation engine scoring strategies in real time
5. Show the automatic rebalancing happening as yields shift

### [1:30 - 2:10] Architecture & Technical Deep Dive
Show the architecture diagram. Walk through:
- "ERC-4626 vault means full composability with the DeFi ecosystem"
- "The StrategyManager routes capital across multiple strategies"
- "Our AI engine scores each strategy by risk-adjusted return"
- "WebSocket updates push real-time yield data to the dashboard"

### [2:10 - 2:40] Security & Trust
Highlight key security features:
- "ReentrancyGuard, Pausable, Emergency Mode"
- "Fee caps baked into the contract -- 5% max management, 30% max performance"
- "Two-step ownership transfer -- no single-point-of-failure"

### [2:40 - 3:00] Close
"Meridian brings institutional-grade yield optimization to every DeFi user on HashKey Chain. One deposit. Maximum yield. Zero guesswork. Try it today."

---

## Quick Start

```bash
# Clone the repository
git clone https://github.com/xpandia/meridian.git
cd meridian

# Install dependencies
npm install

# Set environment variables
export RPC_URL="https://hashkeychain-testnet.alt.technology"
export VAULT_ADDRESS="0x..."
export STRATEGY_MANAGER_ADDRESS="0x..."
export MERIDIAN_API_KEY="your-secret-key"

# Start backend API server
cd src/backend && node server.js

# Open the frontend
open src/frontend/index.html
```

### Contract Deployment (HashKey Chain Testnet)

```bash
# Compile contracts
npx hardhat compile

# Deploy to HashKey Chain testnet
npx hardhat run scripts/deploy.js --network hashkey-testnet
```

---

## Links

- **GitHub:** https://github.com/xpandia/meridian
- **Live Demo:** [TBD after deployment]
- **DoraHacks BUIDL:** [TBD after submission]
- **Demo Video:** [TBD after recording]

---

## License

MIT
