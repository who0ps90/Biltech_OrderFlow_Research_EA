# Validation evidence and limits

Verified locally on 26 October 2026 (Asia/Kuala_Lumpur). The installed MetaEditor/MT5 toolchain was available at `C:/Program Files/XM Global MT5`. Compiler logs are retained under `build/`; runtime identifies MT5 x64 build 6281. No historical-market backtest, optimization or performance evaluation was run.

| Verification | Actual result | Scope |
| --- | --- | --- |
| Main EA compilation | 0 errors, 0 warnings | MQL5 compilation, not execution of order paths |
| Core, order-flow, journal and all-tests source compilation | 0 errors, 0 warnings | Native MQL syntax/type/code generation |
| Native clock/strategy assertions | 52 passed, 0 failed | Real MQL clock/strategy on synthetic fixtures |
| Native order-flow/profile assertions | 41 passed, 0 failed | Real strict importer, OHLC agreement, failure/retest, coverage/profile on synthetic cells |
| Native journal assertions | 19 passed, 0 failed | Real exclusive state serialization/recovery, dirty/truncated state, retired/signal/trade-risk and close-audit preservation |
| Portable Node tests | 41 passed, 0 failed | Independent mathematical/state oracles and source wiring checks; not MQL execution |
| PowerShell helpers | Parsed without errors; installer WhatIf/actual-copy smoke passed | Temporary fake data folder, correct relative includes and four preset copies; no real terminal installed to |

The **112/112** native assertion run used a new portable runtime inside this workspace. Only local terminal/tester executables, shipped default symbol definitions, the compiled no-order test wrapper and synthetic CSV fixtures were copied. No existing terminal account/configuration/credentials/history were copied. Automated trading and DLL imports were disabled; the wrapper required account login zero before running assertions. The runtime closed itself and was removed after results were collected.

Evidence: [native totals](../build/native_result.csv), [native execution log](../build/native.log), [all-tests compiler log](../build/Biltech_AllTests.compile.log) and [main compiler log](../build/compile.log). Reproduce with `scripts/run_native_tests.ps1 -TerminalDirectory '<your MT5 install>'`; reproduce the separate portable tests with `node tests/run_tests.mjs`. The runner relies on [documented MT5 portable/startup settings](https://www.metatrader5.com/en/terminal/help/start_advanced/start); the wrapper omits an input dialog in its main module because [included-file program properties are ignored](https://www.mql5.com/en/docs/basis/preprosessor/compilation).

These tests establish deterministic behavior on the tested inputs. Native tests do not send trades, create positions, use genuine exchange records, measure historical performance or test a broker's live contract calculations. The Node risk/ledger examples are independent specification oracles with source checks; they do not replace account-currency, actual `OrderCalcProfit`, margin, fill-policy, partial-fill, rejection and transaction-order testing in MT5's Strategy Tester. Session/order guards are also reviewed in source; a real-tick end-to-end test remains required.

The first market backtest still requires a verified historical broker-offset schedule, sufficient H1/M5/tick history for one selected symbol, actual fees/execution assumptions and explicit clock acknowledgment. Exchange/profile experiments additionally require matching genuine imported data and conservative complete coverage. The guarded presets intentionally reject initialization until required inputs are supplied. Record sparse/negative results and retain the final holdout untouched.

Publication note: committed build logs preserve test/compiler results but redact absolute personal workspace paths and machine fingerprint lines. Original local logs are kept in ignored build/local-original-logs/.
