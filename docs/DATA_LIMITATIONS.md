# Data and simulation limitations

`PRICE_PROXY` is the portable default. It observes completed H1/M5 prices and two-stage price rejection. It does not measure aggressor delta, traded bid/ask volume, or absorption. Tick counts, candle colour and price changes are never substituted for those quantities.

`EXCHANGE_ORDERFLOW` requires an explicitly imported, documented dataset with volume at price and classified traded buy/sell volume. Initialization fails when required files, manifest, units, classification or declared coverage are invalid; a missing/invalid prior profile rejects that profile and skips entries. It never switches modes silently. The importer validates structural/accounting consistency and compares imported extreme prices with chart A/B and profile-session M5 highs/lows. It cannot independently prove that a supplier's labels are truthful. See [ORDERFLOW_DATA.md](ORDERFLOW_DATA.md).

## Source scope

The supplied strategy description references [the first video](https://www.youtube.com/watch?v=PL7LKUsCgIQ). The implementation treats the user's accompanying description as the source of the stated discretionary elements. A transcript was not available for independent verification. The inaccessible [second video](https://www.youtube.com/watch?v=6XK4yzgT9M0) is excluded. The EA is a proposed deterministic interpretation; it does not reproduce a discretionary trader exactly.

The source-described 4:1 footprint ratio and 20,000-contract M5 MNQ threshold are starting settings, not validated universal parameters. The volume threshold remains disabled by default and is guarded by explicit MNQ/contract-unit selection. Do not apply it to NQ, gold, Dow, CFDs or tick volume.

Gamma exposure is omitted. No options chain, dealer positioning or gamma model is supplied; fabricated gamma would add misleading precision. Discretionary context, profile choice, failure interpretation and trade management are replaced by the explicit research rules in [STRATEGY_SPEC.md](STRATEGY_SPEC.md).

## Time and sessions

- The server-to-UTC schedule is supplied by the researcher for the entire tested period. The present live broker offset is not evidence of a historical offset.
- Schedule intervals are contiguous, half-open UTC ranges. Missing coverage, overlapping or malformed intervals and ambiguous server wall times fail mapping. Broker fallback clock hours cannot uniquely identify UTC from a wall-clock timestamp alone; the EA rejects those timestamps.
- Historical New York DST rules are supported from 1987. Earlier years are rejected. Since 2007, US DST runs from the second Sunday in March to the first Sunday in November, with local 02:00 transitions, as documented by [NIST](https://www.nist.gov/pml/time-and-frequency-division/popular-links/daylight-saving-time-dst). Weekends are excluded. Exchange holidays and early closes are not implemented; restrict runs to the correct calendar or supply corresponding complete data and disclose holiday trades.
- The default entry window is 09:30 inclusive to 11:00 exclusive New York. It corresponds to 21:30–23:00 Malaysia during US daylight time and 22:30–00:00 during US standard time.
- Forced closure occurs at the first available tick at or after the session end. No tick means no immediate executable exit. A restart after the end still requires a tradable tick and successful broker close request.

## Price, execution and accounts

Use the tested symbol's actual tick size, tick value/profit calculation, contract size, volume constraints, account currency, margin rules and trading sessions. A broker's Nasdaq, gold and Dow symbols can represent materially different instruments. The EA uses the current chart symbol, including its suffix; evaluate each instrument separately.

Signal decisions use completed bars. Entry is attempted at the next received tradable tick after confirmation. With gaps, that can be much later than the nominal M5 close. There is no retrospective fill at a bar close. A market order can reject, slip, fill partially or execute outside the requested price. Stops, forced exits and the stated equity risk budget cannot guarantee the final loss under gaps or adverse execution.

Real-tick testing is preferred. OHLC bars cannot determine whether a stop or target was reached first within the same bar. The EA does not synthesize a favourable order; the MT5 tick model controls its execution. Compare ambiguous cases with real ticks and report when only generated ticks are available. Imported order-flow cells do not reconstruct tick-by-tick execution or historical market depth. Current depth is not used to manufacture past order books.

Spread is included through bid/ask execution. Estimated commission and slippage screen and size prospective orders; these assumptions do not add artificial charges to MT5's balance. Actual deal commission, fee and swap are taken from account history. Verify the tester applies the intended fee schedule; do not subtract the same fee twice in evaluation.

On netting accounts another strategy's position on the chart symbol cannot safely be treated as an independent EA position. The EA blocks new entries when a conflicting position exists. Use an isolated tester/account and unique magic/configuration identity. Persistent state is scoped to that identity; do not reuse it across unrelated variants.

## Reproducibility boundaries

Keep a copy of the exact source, compiler/build number, `.set`, symbol specifications, broker clock schedule, imported data/manifest, dates, modelling method, account settings and fees. Record data provenance and a file hash outside MT5 if needed. MT5 history may be revised or downloaded later. Missing M5/H1 history or order-flow cells may reduce usable signals or reject data requirements; do not patch gaps with fabricated activity.

A successful compile and portable model tests are not a completed backtest. Positive results from a small sample or a chosen parameter set are not a profitability claim. Report negative and sparse results and preserve an untouched chronological holdout.
