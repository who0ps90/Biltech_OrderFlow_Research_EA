# Biltech_OrderFlow_Research_EA

A modular MQL5 Expert Advisor for researching a deterministic Nasdaq pullback and rejection interpretation. The default `PRICE_PROXY` mode uses completed H1/M5 prices. It does **not** measure genuine order flow or replicate a discretionary trader exactly. No profitability claim or backtest result is supplied. Outside the MT5 Strategy Tester, order entry is disabled by default.

The supplied strategy description references [Chris Creamer's first video](https://www.youtube.com/watch?v=PL7LKUsCgIQ); the unavailable second video is excluded. See [strategy assumptions](docs/STRATEGY_SPEC.md), [data limitations](docs/DATA_LIMITATIONS.md), [exchange-data format](docs/ORDERFLOW_DATA.md), [audit schema](docs/CSV_SCHEMA.md) and the [evaluation protocol](docs/BACKTEST_EVALUATION.md).

## Layout

- `Biltech_OrderFlow_Research_EA.mq5`: events, order execution, risk, state recovery, audit and optional display.
- `Include/Biltech/`: shared types, historical clock, completed-bar strategy and strict imported order-flow/profile provider.
- `config/`: portable and explicitly experimental tester presets.
- `tests/`: independent portable research oracles, fixture data and evaluation template.
- `scripts/`: compile/install helpers, native assertion sources and an isolated no-order terminal test runner.

## Compile and install on Windows

Use the installed MetaEditor belonging to the MT5 terminal you intend to test. From PowerShell in this project:

```powershell
.\scripts\compile.ps1 -MetaEditor 'C:\Program Files\XM Global MT5\MetaEditor64.exe'
```

Substitute the actual local path when different. The script creates `build/compile.log`, requires a completed compiler result with zero errors and a freshly written EX5, and prints warnings. A compiler process exit code alone is not accepted as proof. For manual compilation, open `Biltech_OrderFlow_Research_EA.mq5` in MetaEditor, press F7 and inspect the Errors panel. Keep the root file beside its `Include/Biltech` directory because quoted relative includes preserve that layout.

In MT5 choose **File → Open Data Folder**. Use that exact folder as `-DataFolder`:

```powershell
.\scripts\install.ps1 -DataFolder 'C:\path\shown\by\MT5' -WhatIf
.\scripts\install.ps1 -DataFolder 'C:\path\shown\by\MT5'
```

The helper copies MQ5/EX5 and local includes into `MQL5/Experts/Biltech_OrderFlow_Research_EA/`, and presets into `MQL5/Profiles/Tester/Biltech_OrderFlow_Research_EA/`. It does not delete existing files, install fabricated data or launch MT5. Refresh Navigator after copying. A compiled EX5 is needed for testing.

## Supply historical broker time mapping

Both modes require a verified server-minus-UTC schedule for the tested period and warm-up history. `InpBrokerClockAcknowledged` deliberately defaults false. A preset is therefore a guarded starting configuration, not an immediately runnable promise. Obtain historical offsets from the broker or documented historical data; never extrapolate today's offset without evidence.

Create a UTF-8 CSV named by `InpBrokerOffsetSchedule`, relative to the EA's MT5 `MQL5/Files` sandbox. The exact header is:

```csv
utc_from,utc_to,offset_minutes
```

Each data row contains `YYYY.MM.DD HH:MM:SS` UTC from/to timestamps and signed integer minutes. Intervals are `[from,to)`, strictly ascending, contiguous, nonoverlapping and bounded to ±840 minutes. An offset of `120` means server wall time = UTC + 2 hours. Include the full test, all warm-up H1/M5 bars and any preceding profile session. Do not insert a guessed example row as real broker evidence. Ambiguous fallback server timestamps and missing schedule coverage are rejected.

MT5 tester agents use their own Files sandboxes. V1 does not declare `tester_file` properties for automatic transfer of runtime-named files. Copy the exact CSVs into the **local test agent's** `MQL5/Files` sandbox and verify initialization can read them; the terminal's ordinary `MQL5/Files` alone may not suffice. Use a local single-agent test. Its directory is normally under the terminal's `Tester` directory or `%APPDATA%/MetaQuotes/Tester/<terminal-id>/Agent-127.0.0.1-<port>/MQL5/Files`; the tester Journal identifies the active agent. The exchange provider files are required only for exchange mode or the optional genuine-volume profile. The [external-data guide](docs/ORDERFLOW_DATA.md) describes the fixtures and provider format; its synthetic fixture is not market data.

After preparing and checking the schedule, set `InpBrokerClockAcknowledged=true` for the test. Leave `InpAllowLiveTrading=false`.

## Run the first backtest

1. Open **View → Strategy Tester** (`Ctrl+R`). Select the installed `Biltech_OrderFlow_Research_EA` and one actual Nasdaq broker symbol, including its suffix. The EA uses that chart/test symbol; it does not hardcode broker names.
2. Set M5, a documented historical development period, initial deposit/account currency/leverage and **Every tick based on real ticks** where the broker has coverage. Start before the New York entry window, using a symbol/history with pre-open ticks. Download/check H1 and M5 history before evaluating missing-history rejections. The H1 context lookback defaults to 512 completed bars; at least 100 H1 and 15 M5 bars must be available, and the pivot pattern may require more history before a setup exists.
3. In Inputs load `config/PRICE_PROXY_PORTABLE.set`. Supply the verified clock schedule, acknowledge it, keep profile off and live permission false. Give the run its own configuration ID. Confirm commission, spread and execution-delay settings in the tester; do not count the same fee twice.
4. Start one test. Inspect initialization messages before interpreting a zero-trade result. A clock/import/coverage rejection is a failed input configuration, not a negative strategy result. Review the audit CSV and tester deal report, including skipped setups and forced closes.
5. Save the tester report, exact inputs, build, clock schedule and data identity with a completed [evaluation template](tests/evaluation_template.csv). Record trade count, net expectancy in R, profit factor, marked-to-market drawdown, streak, exposure, monthly results and sensitivity. Keep the final chronological holdout out of parameter selection.

Research gold second and Dow third as independent experiments with their own contract/cost assumptions. Never carry the MNQ contract-volume threshold into those instruments or CFD tick volume.

The four presets record every current input. All keep live permission and broker-clock acknowledgment false, and all require the real contract's commission assumption to replace the zero placeholder:

| Preset | Purpose |
| --- | --- |
| `PRICE_PROXY_PORTABLE.set` | Proxy confirmation, no profile, frozen swing target |
| `EXPERIMENTAL_FIXED_R.set` | Isolated proxy experiment using a 1.5 net-R target |
| `EXPERIMENTAL_EXCHANGE_ORDERFLOW.set` | Strict imported exchange predicates; profile remains off |
| `EXPERIMENTAL_GENUINE_PROFILE.set` | Proxy confirmation plus imported genuine-volume profile |

These are hypotheses, not optimized settings. The absolute spread cap is in **symbol ticks**, with zero disabling that additional cap; the 10% relative cap always applies. The stop maximum defaults to 1,000 symbol ticks and must be reviewed per contract. Slippage is estimated ticks per side; commission is account currency per lot round turn. `InpDeviationPoints` is in MT5 points, which may differ from ticks.

## Validation and implementation status

Portable tests run with Node.js, without third-party packages:

```powershell
node .\tests\run_tests.mjs
```

They exercise independent mathematical/state oracles and inspect source guard wiring; they do not execute or compile MQL5. Compile the native no-order assertion scripts too:

```powershell
.\scripts\compile.ps1 -MetaEditor 'C:\Program Files\XM Global MT5\MetaEditor64.exe' -SourceRelativePath 'scripts\Biltech_CoreTests.mq5'
.\scripts\compile.ps1 -MetaEditor 'C:\Program Files\XM Global MT5\MetaEditor64.exe' -SourceRelativePath 'scripts\Biltech_OrderFlowTests.mq5'
```

The journal script can be compiled with `-SourceRelativePath 'scripts\Biltech_ExecutionTests.mq5'`. Copy the resulting EX5 files into the terminal's `MQL5/Scripts` directory and `tests/fixtures/*.csv` into `MQL5/Files/Biltech/fixtures`. Refresh Navigator and run each script on a chart; the scripts place no orders. They create/delete dedicated test clock/journal files and read the synthetic fixtures. Inspect the Experts/Journal totals; every assertion must pass.

Alternatively, reproduce all native assertions in a fresh, logged-out portable terminal with automated trading and DLL imports disabled:

```powershell
.\scripts\run_native_tests.ps1 -TerminalDirectory 'C:\Program Files\XM Global MT5'
```

The runner compiles `Biltech_AllTests`, copies only local executable files/default symbol definitions and synthetic fixtures into a fresh workspace runtime, and uses a no-order startup script. It copies no real terminal accounts, credentials, settings or history. A guard refuses execution if an account is logged in or automated trading/DLL imports are allowed. Result/log files remain under `build`; the temporary runtime is removed by default. [MT5's documented startup configuration](https://www.metatrader5.com/en/terminal/help/start_advanced/start) supplies portable/script/shutdown settings.

Actual local verification on 26 October 2026: the EA and native test sources compiled with **0 errors and 0 warnings**. The isolated MT5 build 6281 executed **112 native assertions: 52 clock/strategy, 41 order-flow/profile and 19 journal, all passed**. See [native totals](build/native_result.csv), [native log](build/native.log) and [validation scope](docs/VALIDATION.md). The portable Node suite also passed. **No historical-market backtest was run**, and no performance metrics are claimed.

## Runtime controls and important differences

Baseline risk is 0.25% of current equity, one EA position, at most two entries per New York session, two consecutive losing positions and a 0.50% session equity drawdown gate. Entry uses bid/ask, symbol-specific profit calculations, downward lot-step rounding, margin and broker stop/freeze checks. A spread above 10% of planned stop distance rejects the entry. The fixed cash window and forced session-end closure are research assumptions. Stop orders cannot guarantee the realized loss.

The New York session baseline is account equity on the first tradable tick at or after 09:30, provided the EA observed a tick before that day's 09:30. A cold start in the entry window blocks entries for that day. A cash-only history with no pre-open tick also cannot establish a trusted baseline. Drawdown is measured against this fixed baseline, rather than a rolling equity high, and latches new entries off for that session. All account positions, deposits and withdrawals affect account equity; use an isolated account/tester context. Consecutive losses count fully completed position lifecycles; a flat or positive result resets the sequence. Successful entry orders count once even if the broker splits them into fills.

An exclusive binary journal named `Biltech_state_<account>_<server-hash>_<magic>.bin` resides in the current Files sandbox. It retains the baseline, risk latch, active A/setup, retired setup IDs, last processed M5 bar, last emitted closed trade, submitted trade evidence and original configuration/run identity, fill-time risk snapshot, close-request state and last plan. Dirty/incomplete writes, configuration/symbol mismatches and exclusive-lock conflicts fail closed or block the session. State is restored before processing later bars; at most 512 completed M5 bars are caught up, and only a newly confirmed B on the latest completed bar can enter. A cold start begins with the latest completed bar and does not simulate old trades. Confirmations are consumed and flushed before submission. An uncertain submission remains blocked across restarts and day changes until actual fills/order state establish an unambiguous outcome. Ledger refresh also finalizes a known submitted trade after a restart and records its closure once; new entries wait while the preceding execution audit remains unresolved. Never delete/reset the journal mid-session to bypass limits. Independent tester runs use fresh tester state; retain each run's inputs and exports.

FOK or IOC execution is required. Unsupported RETURN-only fill policies are rejected. Partial IOC fills are handled through the authoritative deal ledger; an unused remainder is not retried. SL/TP protection is attached to the request, and an observed EA position without a protective SL triggers a close attempt. Forced-close intent is journaled before sending. Unknown or merely placed close requests are not duplicated until that exact order's history proves a settled outcome or the position is gone; an indeterminate outcome can require manual review. Inspect actual orders/deals before recovery. The EA blocks existing EA exposure on any symbol and any conflicting exposure/order on the tested symbol, covering netting and hedging accounts conservatively.

Audit files are named `Biltech_audit_<symbol>_<run-id>_<config-hash>.csv` in that same agent Files sandbox. `InpConfigId` plus a deterministic parameter/data hash identifies the configuration; `InpRunId` identifies the exported run. This short hash is for reproducibility bookkeeping, not cryptographic authentication. Change the run ID for independent exports. CSV export and chart display are suppressed during optimization; default display is off. `InpChartVisuals=true` enables frozen zone/reference/target lines and a concise status dashboard for a single test.

Completed-trade rows are snapshots when closure is observed. Late-posted fees/corrections do not rewrite earlier rows; reconcile `DEAL` and `ACCOUNT_DEAL` cash flows against the final MT5 report before treating net results as final. Fill-risk snapshots deduplicate actual deal IDs and require the accounted entry volume to match the completed lifecycle; incomplete risk evidence leaves realized R blank.

When CSV export is enabled outside optimization, initialization also writes `Biltech_config_<run-id>_<config-hash>.txt`. It records the ordered strategy/risk parameters, required input-file hashes, terminal build, account currency, selected symbol specifications and imported dataset identity when used. Retain this snapshot with the exact `.set`, original data and tester report; its checksum does not authenticate a vendor or replace the full broker contract specification.

For the optional exchange/profile experiments, also supply genuine imports and nonempty `InpDataCoverageFromUtc` / `InpDataCoverageToUtc` in ISO UTC (`YYYY-MM-DDTHH:MM:SSZ`). This declared range must include initialization and the entire requested test, and have a positive imported-volume bar at every M5 slot. Closed-market gaps conservatively reject coverage in V1; do not fabricate trades to fill them. Profile initialization immediately checks previous completed cash-session coverage; runtime also requires the imported extremes to match all 78 M5 bars of that cash session before freezing it. This restriction can make multi-day exchange/profile tests unsuitable until a verified no-trade/calendar extension is implemented.

The proxy replaces discretionary failed aggression with strict A/B price evidence. Default profile filtering is off; genuine imported profiles and stricter exchange predicates are separate experiments. Fibonacci anchors, pivot delay, exact chronology, earliest-A selection, ATR definition, fixed expiry and one-attempt consumption make choices that a discretionary trader might change. Gamma, break-even, partial profit-taking and trailing management are omitted in V1. The source-described 4:1 ratio and 20,000-contract MNQ setting have not been validated by the existence of this implementation.
