# Audit CSV schema

`InpExportCSV=true` writes UTF-8, comma-separated audit rows in the current MT5 Files sandbox. Every field is quoted; embedded quotes are doubled. Datetimes use `YYYY.MM.DD HH:MM:SS`. UTC, broker server wall time and New York wall time are named separately; New York wall time is a display value, not a UTC timestamp. Export is disabled during optimization.

Filename: `Biltech_audit_<safe-symbol>_<safe-run-id>_<configuration-hash>.csv`. The run ID is user supplied. Configuration identity includes the selected parameters and hashes of the broker schedule and any required imported files. The short hash is a bookkeeping checksum, not a cryptographic attestation. Reusing the same filename appends rows; use a new run ID for each independent result. Retain the actual source/data/inputs with the export.

With CSV export enabled outside optimization, `Biltech_config_<safe-run-id>_<configuration-hash>.txt` additionally records ordered parameters/input hashes, terminal build, account currency, selected symbol specifications and any imported dataset source/classifier/units. It is a configuration snapshot, not a second trade ledger.

## Field meanings

| Fields | Meaning / units |
| --- | --- |
| `event`, `reason` | Machine-readable event and diagnostic reason, including rejected setups and broker return codes |
| `mode`, `symbol`, `config_id`, `run_id` | Data mode, exact chart symbol, computed configuration identity and run identity |
| `utc`, `server_time`, `new_york_time` | Observation/execution time in UTC, broker wall clock and New York wall clock |
| `decision_bar_server` | Opening timestamp of the completed M5 bar being evaluated, in server wall time |
| `bias`, `direction` | `1` bullish/long, `-1` bearish/short, `0` neutral/absent |
| `setup_id` | Frozen direction/start-pivot/end-pivot identity; namespace with configuration and symbol |
| `armed_utc` | UTC decision time when the setup was armed |
| `anchor_start_utc`, `anchor_start_confirmed_utc`, `anchor_start_price` | Original start pivot, its actual availability time and price |
| `anchor_end_utc`, `anchor_end_confirmed_utc`, `anchor_end_price` | End pivot, availability time and price |
| `zone_low`, `zone_high`, `fib788` | Frozen retracement levels, symbol price units |
| `first_touch_utc` | Opening time of the first M5 bar intersecting the zone |
| `a_utc`, `a_open`, `a_high`, `a_low`, `a_close`, `a_age` | Earliest live A's UTC opening, OHLC and elapsed M5 slots since A |
| `b_utc`, `b_open`, `b_high`, `b_low`, `b_close` | Completed decision-bar UTC opening/OHLC; on a confirmation/submitted-trade record this is the actual B evidence |
| `profile_from_utc`, `profile_to_utc`, `poc`, `val`, `vah` | Frozen previous cash-session profile, half-open UTC coverage and symbol price levels; blank when unused/unavailable |
| `requested_price`, `requested_volume`, `initial_stop`, `target` | Plan before submission; price units and broker lots |
| `spread_price` | Observed ask minus bid, in price units, rather than points/ticks |
| `estimated_net_rr` | Prospective net reward divided by conservative estimated risk, dimensionless |
| `estimated_risk_cash` | Pre-send estimated volume-adjusted stop risk plus estimated costs, account currency |
| `order_ticket`, `deal_ticket`, `position_id` | MT5 order, executed-deal and position lifecycle identifiers; keep as 64-bit integers or text in spreadsheets |
| `executed_price`, `executed_volume` | Actual deal price and executed lots |
| `commission`, `swap`, `fee` | Actual deal components, account currency, signed exactly as MT5 history reports |
| `observed_slippage_ticks` | Signed entry execution difference from the requested price divided by symbol tick size; positive means adverse, blank if correlation is unavailable |
| `exit_reason` | MT5 deal reason such as SL/TP/expert/client; an entry deal also has a reason, so use the event/lifecycle for interpretation |
| `net_result` | Deal net for `DEAL` / `ACCOUNT_DEAL`; complete position net for `TRADE_CLOSED`, account currency |
| `realized_r` | Only populated when the full completed-position initial risk is reconstructible; see below |
| `session_baseline_equity`, `current_equity` | Fixed session baseline and observed account equity, account currency |
| `session_entries`, `consecutive_losses` | Reconstructed successful entry-order count and consecutive completed-position net losses for the New York session |

Setup/pivot/A times are UTC after normalization. Only explicitly named server fields contain broker wall time. Empty timestamps mean unavailable. Some not-yet-applicable setup/plan numeric fields are zero because the record is initialized to zero; these are not zero-price fills. Actual execution/cost fields are blank on nonexecution rows. Unavailable slippage/R/profile values remain blank rather than fabricated.

## Events and aggregation

- `INITIALIZED`, `SESSION_START`, `RISK_LIMIT`: state/baseline and risk-latch changes.
- `SIGNAL_STATE`, `B_CONFIRMED`, `ENTRY_SKIPPED`: completed-bar progression, confirmation evidence and the exact reason an attempt was skipped.
- `PROFILE_FROZEN`, `PROFILE_REJECT`: prior-session profile availability and levels.
- `TIME_REJECT`, `HISTORY_REJECT`, `RESTART_GAP`: clock, history and catch-up limitations.
- `ORDER_REQUEST`, `ORDER_ACCEPTED`, `ORDER_REJECTED`, `CLOSE_REQUEST`: requested broker actions. An accepted request is not by itself proof of a completed fill.
- `DEAL`: one actual executed MT5 deal, including entry commission and partial fills/exits.
- `ACCOUNT_DEAL`: a relevant nontrading MT5 deal such as a fee/correction. It is account cash-flow evidence, not an entry or completed trade; price/volume may be zero.
- `TRADE_CLOSED`: a snapshot of one fully closed position lifecycle when closure is observed, aggregating trading profit, commission, swap and fee then known, including attributable linked costs. This row is an aggregate, not extra cash flow. Its original submitted configuration/run identity is retained across restarts, and a completed-trade flag prevents routine re-emission during ledger refresh. A fee/correction posted later does not rewrite this snapshot.

Use `TRADE_CLOSED` rows as initial completed-trade snapshots, then reconcile any late-posted linked fees/corrections before computing final metrics. For account cash reconciliation use individual `DEAL` and applicable `ACCOUNT_DEAL` rows against the authoritative MT5 report, including separately posted costs not attributable to an EA position. Never sum lifecycle aggregates again with their component cash flows. Reconcile repeated/partial fills by position ID and deal ticket; do not count an order request or each partial fill as a new trade. The deal ledger reconstructs distinct entry **orders**, so multiple fills from one order consume one session entry. External netting/reversals cause a fail-closed ledger limitation. A later positive correction does not retroactively repair an earlier metric snapshot or automatically clear a latched limit.

`realized_r = lifecycle net result known at closure / initial cash-risk snapshot`. At each actual entry fill the denominator adds symbol-specific loss to the original attached stop, including configured adverse exit slippage and estimated round-turn commission. Actual deal IDs are deduplicated independent of callback/ticket ordering, and accounted entry volume must match the complete lifecycle. This account-currency value is saved at fill time and persisted, so later currency conversion changes do not recalculate it. It can differ from `estimated_risk_cash`, which screened an adverse entry assumption before the fill existed. R remains blank when the snapshot is missing, invalid, incomplete or not associated with that position. The submitted setup and B are stored separately from the next developing setup, preserving trade evidence through an exit/restart. Linked nontrading fees are attributed to the lifecycle when possible. Unlinked session costs/corrections block new entries; separately posted adjustments and any resulting final R require reconciliation with the tester/account report.

The audit is an evidence trail, not a replacement for raw imported cells or the MT5 deal ledger. Exchange predicate diagnostics include the first failing reason, and successful/failed predicates must be reproducible from the immutable manifest/cells. Observation timestamps on restart catch-up rows are the current tick; the completed decision-bar and pivot/A availability timestamps identify the historical evidence. No historical entry is sent for a missed older B.
