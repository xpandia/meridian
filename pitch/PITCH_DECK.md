# MERIDIAN — Pitch Deck

> Institutional-grade DeFi yield optimization, for everyone.
> HashKey Chain Horizon Hackathon

---

## Slide 1: Title

# Meridian

**One deposit. Maximum yield. Institutional intelligence.**

Built on HashKey Chain.

*"What if every person on earth had access to the same yield strategies as a crypto hedge fund?"*

---

## Slide 2: The World Has Changed

- $100B+ locked in DeFi protocols today.
- Yields exist everywhere -- lending, liquidity pools, staking, vaults.
- Yet **the average retail user captures less than half** the yield available to them.

Why? Because DeFi was built for engineers, not for people.

---

## Slide 3: The Problem

### Three brutal realities for retail DeFi users:

| Pain | Impact |
|------|--------|
| **Information asymmetry** | Institutions run quantitative models. Retail users guess. |
| **Capital inefficiency** | Funds sit idle in a single pool while better opportunities emerge every block. |
| **Risk blindness** | Most users cannot assess smart contract risk, impermanent loss, or protocol solvency. |

**The result: retail users leave 40-60% of potential yield on the table.**

That is not a gap. That is a canyon.

---

## Slide 4: The Insight

The best hedge funds do not pick *one* strategy. They run **hundreds of models in parallel**, continuously reallocating capital to where risk-adjusted return is highest.

Until now, that required:
- A team of quants
- Custom infrastructure
- Millions in capital

**We took that playbook and put it in a smart contract on HashKey Chain.**

---

## Slide 5: The Solution

# Meridian: AI-Powered DeFi Yield Optimization

```
1. DEPOSIT    ->  Drop assets into a Meridian Vault.
2. OPTIMIZE   ->  Our ML engine scores every strategy by risk-adjusted return,
                  then allocates capital across the optimal set.
3. EARN       ->  The vault auto-compounds and rebalances. Withdraw anytime.
```

**Three steps. No manual farming. No spreadsheets. No missed alpha.**

One interface. One deposit. The intelligence of an entire trading desk working for you, 24/7.

---

## Slide 6: How It Works (Architecture)

```
         USER
          |
    [ Next.js Dashboard ]
          |
    [ The Graph Indexer ]  <-- Real-time on-chain data
          |
    +-----+------+
    |            |
[ Solidity ]  [ ML Engine ]
[ Vaults   ]  [ Risk scoring, yield prediction, rebalance signals ]
    |
[ HashKey Chain ]
```

**Key technical differentiators:**

- **MeridianVault.sol** -- ERC-4626 vault standard. Composable. Auditable.
- **StrategyRouter.sol** -- On-chain execution layer. Receives ML signals, routes capital.
- **Python ML Engine** -- Trained on historical DeFi yield data. Outputs risk-adjusted allocation vectors every epoch.
- **The Graph** -- Indexes all vault events for real-time dashboard + analytics.

---

## Slide 7: Why HashKey Chain

| Advantage | Why it matters for Meridian |
|-----------|-----------------------------|
| **EVM-compatible** | Deploy battle-tested Solidity. No rewrites. |
| **Low gas costs** | Frequent rebalancing becomes economically viable -- critical for an optimizer. |
| **Regulatory clarity** | HashKey is licensed and compliant. Meridian targets retail -- compliance is not optional, it is a feature. |
| **Growing ecosystem** | Early mover advantage. Be *the* yield layer for HashKey Chain DeFi. |

HashKey Chain is not just where we deploy. It is **why** Meridian works.

---

## Slide 8: Market Opportunity

### Total Addressable Market

- **DeFi TVL**: $100B+ and growing
- **Yield aggregation sector**: $15B+ TVL (Yearn, Beefy, Convex)
- **Retail DeFi users**: 10M+ wallets active monthly

### Our Wedge

HashKey Chain's ecosystem is early. That means:
- Less competition
- First-mover vault infrastructure
- Deep partnership potential with launching protocols

**We are not competing in a crowded market. We are building the yield layer for a new chain.**

---

## Slide 9: Business Model

### Performance Fee: 10% of yield generated

| Metric | Conservative | Growth |
|--------|-------------|--------|
| TVL | $10M | $100M |
| Avg. yield | 8% | 12% |
| Annual yield generated | $800K | $12M |
| **Meridian revenue (10%)** | **$80K** | **$1.2M** |

- No deposit fees. No withdrawal fees. No hidden costs.
- We only make money **when users make money**.
- Aligned incentives. Full transparency. On-chain verifiable.

*"If we do not generate yield, we do not eat."*

---

## Slide 10: Traction and Roadmap

### Built during this hackathon:

- Smart contracts deployed to HashKey Chain testnet
- ML model trained on historical DeFi yield data
- Functional dashboard with live vault interaction
- Subgraph indexed and serving real-time queries

### Post-hackathon roadmap:

| Phase | Timeline | Milestone |
|-------|----------|-----------|
| **Alpha** | Q2 2026 | Mainnet launch, single-asset vaults, initial strategies |
| **Beta** | Q3 2026 | Multi-asset vaults, advanced ML models, mobile support |
| **Growth** | Q4 2026 | Cross-chain expansion, institutional API, DAO governance |
| **Scale** | 2027 | $50M+ TVL target, protocol partnerships, token launch |

---

## Slide 11: The Team

| Role | Focus |
|------|-------|
| **Smart Contract Engineer** | Vault architecture, strategy routing, on-chain security |
| **Frontend Engineer** | Dashboard, portfolio visualization, wallet UX |
| **ML / Data Engineer** | Yield prediction models, risk scoring pipeline |
| **Product / Design** | User experience, go-to-market, hackathon narrative |

We are builders. We ship. This entire system was built in a hackathon sprint.

---

## Slide 12: The Ask

### We are building the yield layer for HashKey Chain.

**What we need:**

- HashKey ecosystem grants and partnership support
- Early DeFi protocol integrations on HashKey Chain
- Community and user feedback to refine the product

**What you get:**

- The first institutional-grade yield optimizer purpose-built for your chain
- A product that makes HashKey Chain DeFi accessible to every retail user on earth
- A team that builds fast, thinks deeply, and ships relentlessly

---

### Meridian.

**One deposit. Maximum yield. Institutional intelligence.**

*The future of DeFi is not more complexity. It is less.*

---
