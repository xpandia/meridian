# MERIDIAN -- Technical & Strategic Audit Report

**Auditor:** Senior Technical Auditor (Independent)
**Date:** 2026-03-23
**Scope:** Full codebase, pitch materials, investor documentation, landing page
**Project:** Meridian -- AI-Powered DeFi Yield Optimization on HashKey Chain

---

## Executive Summary

Meridian is a well-architected hackathon project with genuinely strong smart contracts, a polished landing page, and investor-grade pitch materials. The core vault/strategy pattern is sound and leverages proven OpenZeppelin primitives. However, the project suffers from several critical gaps between what the pitch promises and what the code delivers -- most notably the complete absence of the ML/AI engine that is positioned as the core differentiator. The smart contracts are above-average for hackathon work but contain DeFi-specific security issues that would be critical in production.

---

## 1. CODE QUALITY -- 6.5/10

### Strengths
- Clean, well-organized file structure with clear separation of concerns (contracts, backend, frontend, pitch)
- Consistent code style across Solidity, JavaScript, and HTML
- Good use of NatSpec comments in contracts
- Custom errors instead of revert strings (gas-efficient and modern)
- Backend code is well-structured with proper middleware layering

### Weaknesses
- **No tests exist.** Zero unit tests, zero integration tests, zero deployment scripts beyond a reference in the README. For a DeFi vault holding user funds, this is a serious deficiency.
- **No Hardhat/Foundry configuration file.** The README references `npx hardhat compile` and `npx hardhat run scripts/deploy.js` but no `hardhat.config.js`, `foundry.toml`, or `scripts/` directory was found.
- **No CI/CD pipeline, no linting configuration, no formatting enforcement.**
- **The ML engine referenced everywhere does not exist.** The README, pitch deck, architecture diagrams, and landing page all reference a "Python ML Engine" with yield prediction and risk scoring. There is no `ml/` directory, no Python code, no model artifacts. This is the project's claimed core differentiator and it is entirely missing.
- **The subgraph referenced does not exist.** "The Graph Indexer" is shown in architecture diagrams. No `subgraph/` directory, no `schema.graphql`, no mappings.
- The README project structure shows directories (`contracts/`, `subgraph/`, `ml/`) that do not match the actual structure (`src/contracts/`, no subgraph, no ml).

---

## 2. LANDING PAGE -- 8.5/10

### Strengths
- **Visually excellent.** Professional-grade design that would not look out of place for a funded DeFi protocol. Clean dark theme, gold accent palette, strong typographic hierarchy.
- **Self-contained single HTML file (~1,930 lines).** No build step required. Loads fast. Hackathon-friendly.
- **Animated yield chart** on canvas is well-implemented with Bezier curves, gradient fills, live-updating data points, and a glowing dot. Impressive for a single-file implementation.
- **Responsive design** with three breakpoints (1024px, 768px, 480px). Mobile nav toggle implemented.
- **Scroll reveal animations** with IntersectionObserver -- modern, performant, no jQuery.
- **Content sections are comprehensive:** Problem, Solution, How It Works, Live Strategies (6 strategy cards with sparklines), Security, CTA, Footer.
- **Animated hero counters** with easing.

### Weaknesses
- **All data is hardcoded/simulated.** The "18.42% APY," "$124,891 Net Value," "$2.4M TVL" and all strategy cards show fabricated numbers with no connection to any backend or contract. This is fine for a hackathon demo but the "Live" badge in the chart header is misleading.
- **No wallet connection.** The "Launch App" and "Start Earning" buttons are dead links (`href="#"` and `href="#cta"`). For a DeFi product, not having even a MetaMask connect flow is a gap.
- **Mobile nav implementation is fragile** -- uses inline style manipulation rather than CSS classes. The mobile nav does not have a close-on-outside-click handler.
- **No favicon, no OG meta tags, no SEO metadata.**
- **Security section claims "Audited Smart Contracts" and "Timelock Governance"** -- neither exists in the codebase. The contracts have no timelock, and no audit has been performed. This is a credibility risk if judges inspect the code.
- Missing `</html>` closing tag (minor).

---

## 3. SMART CONTRACTS -- 7.5/10

### Strengths
- **ERC-4626 compliance.** Using the OpenZeppelin ERC4626 base is the correct architectural choice. The vault is composable with the broader DeFi ecosystem out of the box.
- **Ownable2Step.** Two-step ownership transfer prevents accidental ownership loss -- good practice.
- **ReentrancyGuard on all state-changing external functions.** Both `_deposit`, `_withdraw`, `harvest`, `compound`, `emergencyWithdraw` in the Vault, and `deployAssets`, `withdrawAssets`, `harvest`, `emergencyWithdrawAll`, `rebalance` in StrategyManager are protected.
- **Pausable + Emergency Mode** -- dual-circuit breaker design. Emergency mode pulls all funds from strategies and pauses deposits while still allowing withdrawals. This is well-designed.
- **Slippage protection** in `withdrawAssets` with configurable tolerance.
- **Dust handling** in `deployAssets` -- leftover wei from rounding goes to the first active strategy.
- **Fee validation** with MAX constants (5% management cap, 30% performance cap).
- **Custom errors** for gas efficiency.
- **Compound cooldown** prevents MEV abuse of the compound function.
- **SafeERC20 used throughout** -- no raw `transfer` calls.

### DeFi Security Issues (Critical for Production)

#### P0 -- Critical

1. **emergencyWithdraw() has no slippage protection and can be drained.**
   ```solidity
   function emergencyWithdraw(uint256 shares) external nonReentrant {
       uint256 assets = convertToAssets(shares);
       _burn(msg.sender, shares);
       IERC20(asset()).safeTransfer(msg.sender, assets);
   }
   ```
   This function calculates `assets` via `convertToAssets` (which uses `totalAssets()`) but then transfers from the vault's idle balance. If the vault's idle balance is less than the computed assets (because most funds are deployed in strategies), this will revert on the `safeTransfer` -- or worse, if multiple users race to emergency withdraw, the last users get nothing. There is no proportional logic that accounts for actually available idle funds. This is a **bank run vulnerability** in emergency mode.

2. **Flash loan attack vector on harvest().** The `harvest()` function is callable by anyone (`external nonReentrant whenNotPaused` -- no access control beyond pause). An attacker could:
   - Flash loan a large amount of the underlying asset
   - Deposit into the vault (getting shares)
   - Call `harvest()` to realize profits
   - The attacker's shares now represent a larger portion of the newly harvested profits
   - Withdraw and repay flash loan

   Mitigation: add access control to `harvest()` (onlyOwner or a keeper role), or implement a deposit-to-harvest delay.

3. **No timelock on critical admin functions.** `setStrategyManager()`, `setFees()`, `setFeeRecipient()`, and `setDepositLimit()` are all instant. A compromised owner key can instantly redirect all vault assets to a malicious strategy manager, set fees to maximum, or change the fee recipient. The landing page claims "48-hour timelock governance" -- this does not exist.

#### P1 -- High

4. **Management fee calculation uses `lastCompoundTimestamp` incorrectly.** The `collectManagementFee()` function calculates elapsed time from `lastCompoundTimestamp`, but this timestamp is also updated by `compound()`. If `compound()` is called frequently, the management fee accrual resets to zero each time. If `compound()` is never called, the management fee could accumulate to an enormous amount in a single call. This creates either fee avoidance or fee spiking depending on compound frequency.

5. **Rounding error in fee share minting.** The formula `(totalSupply() * managementFee * elapsed) / (FEE_DENOMINATOR * 365 days)` can lose precision when `totalSupply` is small. More critically, there is no minimum supply check -- if totalSupply is 0, the function returns 0 shares but should not be callable at all.

6. **StrategyManager: `removeStrategy` does not clean up `strategyIndex` mapping.** After calling `removeStrategy`, `strategyIndex[strategy]` still returns the old index. If a strategy is removed and a new strategy is added, the index mapping becomes stale. The strategy is marked `active = false` but never deleted from the array, so `strategies.length` grows monotonically.

7. **Oracle manipulation risk.** `totalAssets()` depends on `strategyManager.totalDeployedAssets()` which sums `IStrategy.balanceDeployed()` across all strategies. If any strategy's `balanceDeployed()` can be manipulated (e.g., it reads from an AMM pool that can be sandwiched), the vault's share price becomes manipulable. This enables share price inflation/deflation attacks on deposit/withdraw.

8. **No withdrawal fee or delay.** Combined with the flash loan vector above, instant withdrawals with no fee allow atomic arbitrage of the vault.

#### P2 -- Medium

9. **`maxMint` calls `convertToShares(maxDeposit(receiver))` which can revert** if maxDeposit returns a very large number and totalSupply is 0 (division by zero in the conversion).

10. **Unlimited approval to strategy manager.** `forceApprove(manager_, type(uint256).max)` -- while this is gas-efficient, it means a compromised or malicious strategy manager can drain the entire vault in a single transaction. Consider approving only the amount being deployed.

11. **No strategy interface validation.** `addStrategy` in StrategyManager accepts any address. There is no check that the address actually implements the `IStrategy` interface. A misconfigured strategy address would cause silent failures.

12. **Rebalance function is owner-only.** If the owner key is lost or unavailable, rebalancing cannot occur, and capital remains stuck in suboptimal allocations indefinitely.

### What is Missing
- No actual strategy implementations (only the IStrategy interface)
- No deployment scripts
- No test suite
- No formal verification
- No timelock contract
- No governance mechanism

---

## 4. BACKEND -- 7.0/10

### Strengths
- **Well-structured Express.js API** with proper middleware stack: Helmet (security headers), CORS, rate limiting (120 req/min), JSON parsing.
- **Clean route organization:** `/api/health`, `/api/vault`, `/api/yield`, `/api/portfolio/:address`, `/api/recommendations`, `/api/strategies`, `/api/risk`, `/api/history`, `/api/harvests`.
- **Contract guard middleware** (`requireContracts`) gracefully handles uninitialized state with 503 responses.
- **Risk metrics computation** is thoughtful: HHI-based diversification index, weighted risk scoring, max drawdown estimation, concentration risk classification.
- **Recommendation engine** provides actionable signals (REDUCE_WEIGHT, INCREASE_WEIGHT, REVIEW, DIVERSIFY, REBALANCE) based on risk tolerance and ROI -- this is a credible "AI-lite" feature.
- **On-chain event querying** for harvest history.
- **Input validation** on portfolio address endpoint using `ethers.isAddress()`.
- **Module exported** for testing via `module.exports = app`.

### Weaknesses
- **No authentication or authorization.** Any client can query any user's portfolio data, strategy details, and vault internals. For a production API, sensitive endpoints should require authentication.
- **No input sanitization** on `req.query.blocks`, `req.query.limit`, `req.query.from` -- `parseInt` is used directly without bounds validation (aside from `Math.min` on limit). Negative values, NaN, or extreme values could cause issues.
- **History endpoint is trivially DoS-able.** The `from` query parameter is not validated, and the in-memory snapshot array has no authentication -- any client can trigger snapshot recording by hitting `/api/vault` repeatedly.
- **No WebSocket support.** For a real-time DeFi dashboard, REST polling is suboptimal. The "Live" badge on the frontend implies real-time data, but the backend only supports request-response.
- **Sharpe ratio calculation is a placeholder.** `totalProfit / weightedRisk` is not a Sharpe ratio -- it does not account for risk-free rate, return variance, or time normalization. Labeling this "Sharpe" in the API response is misleading.
- **No environment variable validation.** The server starts with `ethers.ZeroAddress` as default contract addresses, which means it boots in a broken state silently.
- **No logging framework.** Only `console.log` and `console.error` are used. No structured logging, no request logging, no audit trail.
- **No graceful shutdown handler.**
- **package.json has no lockfile, no dev dependencies** (no testing framework, no linter).

---

## 5. PITCH MATERIALS -- 9.0/10

### Strengths
- **PITCH_DECK.md is outstanding for a hackathon.** 12 well-structured slides following a proven narrative arc: problem, insight, solution, architecture, why-this-chain, market, business model, traction/roadmap, team, ask.
- **pitch_deck.html is a fully interactive HTML slide deck** (~640 lines) with keyboard navigation, progress bar, slide counter, speaker notes panel, animated transitions, counter animations, animated bar charts, TAM/SAM/SOM concentric circle visualization, roadmap timeline, competitive comparison grid, team cards, and funding donut chart. This is exceptionally polished for hackathon pitch materials.
- **DEMO_SCRIPT.md is professionally structured** with exact timestamps, speaker dialogue, screen actions, a pre-demo checklist, and a fallback plan. The 3-minute timing is realistic and well-paced.
- **VIDEO_STORYBOARD.md is production-quality** -- scene-by-scene breakdown with visual descriptions, motion direction, voiceover scripts, typography specs, color palette, music references, and a timing summary. This document alone shows serious product thinking.
- **Messaging is crisp and consistent.** "One deposit. Maximum yield. Institutional intelligence." appears consistently across all materials. The "Wealthfront for DeFi" positioning is clear and defensible.
- **Competitive positioning** is specific and credible (vs. Yearn, Beefy, Convex, manual farming).

### Weaknesses
- **The pitch claims "Smart contracts deployed to HashKey Chain testnet," "ML model trained," "Subgraph indexed."** If judges verify, they will find no deployment evidence, no ML model, and no subgraph. This creates a credibility gap.
- **The architecture diagram in the pitch references "StrategyRouter.sol"** but the actual contract is called "StrategyManager.sol." Inconsistency suggests the pitch was written before (or independently from) the code.
- **Revenue projections ($80K-$6M over 3 years) assume TVL growth** from $10M to $500M without substantiating user acquisition strategy beyond generic DeFi marketing channels.
- The pitch references "Next.js Dashboard" but the frontend is a static HTML file, not a Next.js app.

---

## 6. INVESTOR READINESS -- 8.0/10

### Strengths
- **INVESTOR_BRIEF.md is a legitimate investor memo.** It covers all sections a pre-seed investor expects: one-liner, quantified problem, solution differentiation, why-now thesis, TAM/SAM/SOM, unit economics, competitive moat analysis, GTM strategy, business model, 3-year financial projections, team requirements, funding ask ($1.5M at $6-10M post-money), risk/mitigation matrix, and exit strategy.
- **Unit economics are specific and reasonable.** $20K average deposit, $600 LTV, 12-30x LTV:CAC, 90%+ gross margin, 2-4 month CAC payback -- these are credible DeFi protocol economics.
- **Risk section is honest.** Acknowledges smart contract vulnerability, ML model failure, ecosystem risk, regulatory risk, and cold-start TVL bootstrapping.
- **Use of funds is detailed** with specific allocations (47% engineering, 17% audits, 13% growth, 13% ops, 10% reserve) and milestone-based tranches.
- **Comparable exits and acquisition targets** are well-researched (Yearn, Sommelier, Convex, Idle).

### Weaknesses
- **No team names, backgrounds, or credentials.** The team section lists roles but not people. For an investor brief, this is a significant omission -- investors fund teams, not ideas.
- **$300-500M TVL by Year 3 is aggressive** for a single-chain protocol on a nascent ecosystem. The brief does not adequately justify this growth trajectory.
- **The "data moat" argument is weak.** The claim that ML models improve with more TVL data creating a flywheel is theoretically sound but unproven -- no model exists to validate this claim.
- **Exit valuations ($50M-$400M) are speculative** and based on peak-market comparables from 2020-2021 that may not repeat.
- **The brief says "Performance fee only (no management fee that resembles fund management)"** but the smart contract actually implements a management fee (`collectManagementFee`). Contradiction.

---

## 7. HACKATHON FIT -- 7.5/10

### Strengths
- **Strong alignment with HashKey Chain Horizon Hackathon.** The project is purpose-built for HashKey Chain with clear articulation of why the chain's properties (low gas, EVM compatibility, regulatory status) specifically benefit the product.
- **DeFi infrastructure is a high-value hackathon category.** Yield optimization is a proven product category with real demand.
- **Pitch materials are among the best you will see at a hackathon.** The HTML slide deck alone would set this apart from most submissions.
- **The smart contracts are substantive.** Two well-designed contracts totaling ~840 lines of Solidity with real DeFi logic is solid hackathon output.
- **The backend API demonstrates a functional data layer** with 9 endpoints and meaningful business logic.

### Weaknesses
- **The core claimed differentiator (ML/AI engine) does not exist.** This is the most significant gap. The project is positioned as "AI-Powered DeFi" but contains zero AI/ML code. The backend has a rule-based recommendation engine, which is a reasonable substitute, but it is not machine learning.
- **No deployed contracts.** The README checklist items are all unchecked. No testnet deployment evidence.
- **No working dApp.** The landing page is a marketing site, not an application. Users cannot connect a wallet, deposit, or interact with any contract.
- **The frontend references "Next.js" and "TypeScript" in the tech stack but delivers a single static HTML file.** This is a mismatch that attentive judges will notice.
- **No subgraph, no The Graph integration** despite being listed as a core architecture component.

---

## 8. CRITICAL ISSUES

| # | Issue | Severity | Category |
|---|-------|----------|----------|
| 1 | **ML/AI engine does not exist** -- the core product differentiator is missing entirely | CRITICAL | Deliverable gap |
| 2 | **emergencyWithdraw() bank run vulnerability** -- users racing to withdraw will find insufficient idle funds | CRITICAL | Smart contract security |
| 3 | **harvest() is permissionless** -- enables flash loan profit extraction | CRITICAL | Smart contract security |
| 4 | **No timelock on admin functions** despite landing page claiming "48-hour timelock governance" | HIGH | Security + credibility |
| 5 | **No tests, no deployment, no working dApp** | HIGH | Deliverable completeness |
| 6 | **Inconsistencies between pitch claims and actual code** (Next.js vs HTML, StrategyRouter vs StrategyManager, ML engine, subgraph) | HIGH | Credibility |
| 7 | **Management fee calculation depends on compound timing** -- exploitable by either caller | MEDIUM | Smart contract logic |
| 8 | **No strategy implementations exist** -- only the interface | MEDIUM | Deliverable gap |
| 9 | **Sharpe ratio calculation is mathematically incorrect** | LOW | Backend logic |
| 10 | **README project structure does not match actual structure** | LOW | Documentation |

---

## 9. RECOMMENDATIONS

### P0 -- Do Before Submission

1. **Add access control to `harvest()`.** Add `onlyOwner` or a dedicated keeper role. This closes the flash loan attack vector. (15-minute fix)

2. **Fix `emergencyWithdraw()`.** Either (a) pull from strategies before transferring (like `_withdraw` does), or (b) cap the transfer to `min(assets, idleBalance)` and document that emergency withdrawals are limited to idle funds. (30-minute fix)

3. **Align pitch claims with reality.** Either:
   - Remove ML/AI claims and position as a "rule-based yield optimizer" (honest but weaker), OR
   - Build a minimal Python script that outputs allocation weights based on historical APY data and call it from the backend. Even a simple mean-variance optimizer would substantiate the "ML" claim. (2-4 hours)

4. **Deploy contracts to HashKey Chain testnet** and include the deployment addresses in the README. (1 hour)

5. **Fix the README** project structure to match reality. Remove references to non-existent directories. (15 minutes)

### P1 -- Do If Time Permits

6. **Add a basic test suite.** Even 5-10 Foundry/Hardhat tests covering deposit, withdraw, harvest, and emergency mode would dramatically strengthen the submission. (3-4 hours)

7. **Add a timelock to `setStrategyManager()`.** This is the most dangerous admin function. Even a simple 24-hour delay would demonstrate security awareness. (1-2 hours)

8. **Add wallet connection to the landing page.** Use ethers.js (already in backend dependencies) to add MetaMask connect. Even a non-functional "Connect Wallet" button that shows a connected address would demonstrate frontend-contract awareness. (1-2 hours)

9. **Add `lastDepositTimestamp` per user** and require a minimum delay (e.g., 1 block) between deposit and harvest to mitigate flash loan attacks at the contract level. (1 hour)

10. **Fix management fee accounting.** Use a separate `lastFeeCollectionTimestamp` independent of `lastCompoundTimestamp`. (30 minutes)

### P2 -- Post-Hackathon

11. **Implement at least one concrete strategy** (e.g., a simple lending strategy wrapping an Aave/Compound-style protocol on HashKey Chain).

12. **Build the ML engine.** Start with a simple model: historical APY data + volatility + TVL as features, risk-adjusted return as target. scikit-learn random forest would be sufficient for v1.

13. **Add comprehensive test coverage** (target 90%+) including fuzzing for arithmetic operations.

14. **Implement timelock governance** for all admin functions.

15. **Get a professional audit** before any mainnet deployment.

16. **Build the actual Next.js dashboard** with wallet integration, deposit/withdraw flows, and real-time vault data.

17. **Add WebSocket support** to the backend for real-time dashboard updates.

18. **Fix the Sharpe ratio calculation** or remove it from the API.

---

## 10. OVERALL SCORE

| Category | Score | Weight | Weighted |
|----------|-------|--------|----------|
| Code Quality | 6.5/10 | 15% | 0.975 |
| Landing Page | 8.5/10 | 10% | 0.850 |
| Smart Contracts | 7.5/10 | 25% | 1.875 |
| Backend | 7.0/10 | 10% | 0.700 |
| Pitch Materials | 9.0/10 | 15% | 1.350 |
| Investor Readiness | 8.0/10 | 10% | 0.800 |
| Hackathon Fit | 7.5/10 | 15% | 1.125 |

### **OVERALL: 7.68 / 10**

---

### Verdict

**Meridian is a strong hackathon project with a significant honesty problem.**

The smart contracts are genuinely well-written and demonstrate real DeFi engineering knowledge. The pitch materials are among the best I have seen for hackathon-stage projects -- the HTML slide deck alone is exceptional. The investor brief is thorough enough to start real conversations.

However, the project's central claim -- "AI-Powered DeFi" -- is currently unsupported by any code. The ML engine, The Graph subgraph, and the Next.js dashboard referenced throughout all materials do not exist. The landing page claims audited contracts and timelock governance that are not implemented. These gaps create a credibility risk that could undermine an otherwise impressive submission.

The smart contracts have real security vulnerabilities (permissionless harvest, emergency withdraw race condition) that would be critical in production but are forgivable at hackathon stage -- provided they are acknowledged rather than hidden behind claims of "audited" status.

**If the team spends 4-6 focused hours on P0 fixes (access control on harvest, emergency withdraw fix, contract deployment, README alignment, and either building a minimal ML component or honestly repositioning the messaging), this project moves from "good hackathon project with credibility issues" to "genuinely impressive and fundable."**

The bones are strong. The pitch is polished. The contracts work. Fix the truth gap and this is a contender.

---

*Report generated 2026-03-23. This audit is advisory and does not constitute a formal security audit. Smart contracts should undergo professional security review before any mainnet deployment with real user funds.*
