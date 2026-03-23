# Meridian

**Institutional-grade DeFi yield optimization, for everyone.**

---

## The Problem

DeFi yields are fragmented across dozens of protocols, chains, and strategies. Retail users face three brutal realities:

1. **Information asymmetry** -- Institutions run quantitative models to find alpha. Retail users guess.
2. **Capital inefficiency** -- Funds sit idle in single pools while better opportunities emerge every block.
3. **Risk blindness** -- Most users cannot assess smart contract risk, impermanent loss exposure, or protocol solvency.

The result: retail leaves 40-60% of potential yield on the table.

## The Solution

Meridian is a rule-based yield optimizer deployed on HashKey Chain. It continuously analyzes on-chain data, scores risk-adjusted returns, and automatically rebalances user positions across the highest-performing DeFi strategies -- all within a single vault interface.

One deposit. Maximum yield. Institutional intelligence.

## How It Works

```
1. DEPOSIT    -->  User deposits assets into a Meridian Vault on HashKey Chain.
2. OPTIMIZE   -->  Our recommendation engine scores every available strategy by
                   risk-adjusted return, then allocates capital across the optimal set.
3. EARN       -->  The vault auto-compounds and rebalances. Users withdraw anytime.
```

Three steps. No manual farming. No spreadsheet tracking. No missed opportunities.

## Architecture

```
                    +---------------------+
                    |   Landing Page      |
                    |   (Static HTML)     |
                    +---------+-----------+
                              |
                    +---------v-----------+
                    |   Express.js API    |
                    |   (REST + WebSocket |
                    |    real-time data)  |
                    +---------+-----------+
                              |
                    +---------v-----------+
                    |  Solidity Contracts |
                    |  (MeridianVault,    |
                    |   StrategyManager)  |
                    |                     |
                    |  HashKey Chain EVM  |
                    +---------------------+
```

## Tech Stack

| Layer        | Technology                          |
|--------------|-------------------------------------|
| Chain        | HashKey Chain (EVM-compatible)       |
| Contracts    | Solidity 0.8.x, OpenZeppelin        |
| Backend      | Node.js, Express, ethers.js, WebSocket |
| Frontend     | Static HTML/CSS/JS landing page     |

## Project Structure

```
04-Meridian/
├── README.md
├── docs/
│   └── AUDIT_REPORT.md
├── src/
│   ├── contracts/         # Solidity smart contracts
│   │   ├── MeridianVault.sol
│   │   └── StrategyManager.sol
│   ├── backend/           # Express.js API server
│   │   └── server.js
│   └── frontend/          # Landing page
│       └── index.html
└── pitch/                 # Pitch materials
    ├── PITCH_DECK.md
    ├── pitch_deck.html
    ├── DEMO_SCRIPT.md
    ├── VIDEO_STORYBOARD.md
    └── INVESTOR_BRIEF.md
```

## Smart Contract Security

The vault and strategy manager implement the following security measures:

- **ERC-4626 compliance** via OpenZeppelin base
- **Ownable2Step** -- two-step ownership transfer prevents accidental loss
- **ReentrancyGuard** on all state-changing functions
- **Pausable + Emergency Mode** -- dual circuit breaker design
- **Access-controlled harvest** -- `harvest()` is `onlyOwner` to prevent flash-loan profit extraction
- **Safe emergency withdrawals** -- capped to idle balance to prevent bank-run reverts
- **Slippage protection** on strategy withdrawals
- **Fee caps** -- 5% max management fee, 30% max performance fee
- **SafeERC20** -- no raw transfer calls

> **Note:** These contracts have not undergone a formal security audit. They should be professionally audited before any mainnet deployment with real user funds.

## Team

| Role                     | Responsibility                                |
|--------------------------|-----------------------------------------------|
| Smart Contract Engineer  | Vault architecture, strategy routing, security |
| Frontend Engineer        | Dashboard, portfolio visualization, wallet UX  |
| Backend Engineer         | API, risk metrics, recommendation engine       |
| Product / Design         | User experience, hackathon narrative, demo flow |

## Hackathon Submission Checklist

- [ ] Smart contracts deployed to HashKey Chain testnet
- [ ] Frontend dashboard connected to live contracts
- [ ] Demo video recorded (< 3 minutes)
- [x] Pitch deck finalized
- [ ] DoraHacks BUIDL page submitted
- [x] README complete with architecture + instructions

## Local Development

```bash
# Install dependencies
npm install

# Start backend API server
cd src/backend && node server.js

# Environment variables (optional)
export MERIDIAN_API_KEY="your-secret-key"
export VAULT_ADDRESS="0x..."
export STRATEGY_MANAGER_ADDRESS="0x..."
export RPC_URL="https://hashkeychain-testnet.alt.technology"
```

## License

MIT

---

*Built for the HashKey Chain Horizon Hackathon on DoraHacks.*
