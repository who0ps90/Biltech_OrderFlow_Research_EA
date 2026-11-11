# Backtest evaluation protocol

No performance claim is supplied. Complete the following for each symbol, data mode and management variant independently. Research Nasdaq first, gold second and Dow third; do not pool their economics or copy volume thresholds between them.

## Before the first run

1. Choose one broker symbol and record the exact contract, tick size, volume step/minimum/maximum, account currency, leverage and commission schedule.
2. Preserve the data source, source revision, hashes where available, clock schedule and the `.set`. Exchange mode also needs its manifest/cells and coverage checks.
3. Set chronological development dates, then validation dates, then a final holdout before looking at their results. Keep the final holdout untouched during selection. Do not repeatedly re-label a tested period as unseen.
4. Use `Every tick based on real ticks` when the broker has sufficient coverage. Record unavailable ticks, generated segments, execution delay, spread assumptions and fees. Run adverse spread/slippage/fee scenarios as separate named experiments.
5. Use the portable proxy baseline first: H1/M5, profile off, swing target, no break-even, no partial exit, no trailing. Keep live permission off.

## Required report

Copy [evaluation_template.csv](../tests/evaluation_template.csv) for one row per run. Record at least:

- Run ID, code revision/hash, MT5 compiler/tester build, exact symbol, data provider, mode, configuration ID, period and development/validation/holdout role.
- Modelling method, history quality/coverage, account settings, fees, spread and execution delay assumptions.
- Trade count and number of usable sessions; counts of rejection reasons and import/mapping failures.
- Net expectancy in R, net profit factor, maximum equity drawdown in account currency and percent, longest consecutive losing trade streak, time in market, and monthly results.
- Parameter sensitivity, sample limitations and any same-bar stop/target cases.

Compute net result as trading profit plus commission, fee and swap. `TRADE_CLOSED` rows are completed-position snapshots with costs known at closure, not retroactively rewritten final accounting. Reconcile late-posted linked fees/corrections from `DEAL` / `ACCOUNT_DEAL` and the final MT5 report before calculating final metrics; never sum both snapshot aggregates and component cash flows. Exported realized R divides net result known at closure by initial stop-based cash risk snapshotted at each actual entry fill, including configured adverse exit slippage and estimated round-turn commission. Its account-currency conversion is retained from fill time. It can differ from the pre-send `estimated_risk_cash`, which also assumed adverse entry slippage. If the original risk snapshot is missing, invalid or accounts for incomplete entry volume, R is blank; do not replace it with zero. Adjust final net/R separately when later attributable costs change the result. Aggregate a position's fills/exits once before counting a completed trade. Profit factor is gross positive **net trade** outcomes divided by the absolute gross negative net trade outcomes; with no losing trades report undefined, rather than an arbitrary huge number. Do not average ratios across runs.

Equity drawdown uses marked-to-market equity; balance drawdown omits floating loss. Exposure is elapsed time with an EA position divided by eligible test elapsed time, with the denominator disclosed. Monthly results should include trade count, net account-currency P/L and mean R, including zero-trade months. R is dimensionless; do not sum account currencies from separate accounts.

## Sensitivity and review

Test a small predeclared neighbourhood of pivot wings, expiry, minimum R, stop buffer and cost assumptions. Report the full neighbourhood, not only its winner. Keep profile and exchange-order-flow experiments distinct from proxy results. Any management variant is a separate hypothesis and should retain its own configuration ID and holdout accounting.

Inspect CSV evidence for no-look-ahead timestamps, changed bias, expired setups, spread/risk rejections, duplicate/rejected orders and forced closes. For ambiguous intrabar execution inspect tick-level history; do not overwrite tester outcomes with favourable OHLC assumptions. Reconcile audit P/L with the tester deal ledger, especially fees, partial fills, restart recovery and final liquidation.

Report uncertainty with the observed sample size, number of independent sessions, concentration by month and losing streak. Sparse samples and negative results remain valid research outputs. A compile, synthetic fixture pass, or illustrative risk example provides no evidence of a profitable strategy.
