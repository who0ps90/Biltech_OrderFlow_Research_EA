# Exchange import and previous-session profile

`PRICE_PROXY` is the portable default. It uses price rejection and does not measure aggressor delta, absorption, traded bid/ask volume, or exchange participation. `EXCHANGE_ORDERFLOW` is an experimental import mode. There is no feed connector, tick-rule classifier, historical DOM reconstruction, or automatic conversion of broker tick volume in V1. Failure to load required exchange inputs rejects initialization; a missing queried interval rejects the signal or profile. There is no fallback to proxy evidence.

`IOrderFlowProvider` defines the import, coverage, failure, retest and profile interface. `CExchangeProvider` implements it with immutable-in-memory CSV inputs after loading. Its metadata checks validate importer declarations and internal consistency. They cannot authenticate a vendor, prove that classifications are accurate, or prove that an importer has included every exchange trade. A researcher must retain the raw source, documentation, import code, file hashes and classification audit with each evaluation.

## Required data

Use actual exchange trades aggregated by **UTC M5 opening timestamp and exact traded price**, with mutually exclusive buy-aggressor, sell-aggressor and unknown buckets. Each traded contract/share must enter exactly one bucket once. Buy/sell means the aggressor's side, not both counterparties, resting-book size, candle direction, price-change direction, or the number of quote updates. Zero-volume cells are omitted. Unknown classifications are explicit; never silently discard them from total traded volume.

The supported classifiers are:

- `exchange_aggressor_flag`: an actual documented exchange aggressor field. Record the relevant field, feed specification/version and any unmatched/corrected trade policy in `classifier_details` and an accompanying audit.
- `quote_match_at_trade`: a documented contemporaneous trade/quote match. Record the quote source, clock synchronization, sequence handling, bid/ask rule, locked/crossed market handling and treatment of trades at neither quote. Unresolved cases belong in `unknown_volume`. A last-price uptick/downtick rule is prohibited.

Both labels are importer assertions. The provider cannot inspect the original tick records to verify them. Any other classifier label, including `price_change`, is refused. The optional minimum bar volume is accepted only with exact `instrument=MNQ` and `units=contracts`. It is disabled by default. Its source-described starting value of 20,000 contracts is not transferred to NQ, gold, Dow, shares, CFD lots, or broker tick counts.

The chart history must represent the same unadjusted instrument/contract and price grid as the import. Naming an MNQ file after a CFD chart symbol does not make their prices equivalent. Cross-market price/basis mapping is unsupported. The manifest symbol must match the selected chart symbol exactly, including its suffix; the provider also validates each imported price against that chart's tick size. `ValidateBar` requires the same completed UTC M5 interval's chart low/high to exactly match the imported lowest/highest traded tick. It rejects both missing extremes and imported prices outside the chart range. This cross-check can detect inconsistent series, but aggregated cells do not retain enough trade sequence to authenticate chart opens/closes or the vendor's identity.

## Manifest

Use UTF-8 text, comma separators and the exact `key,value` header. All 14 keys below are mandatory, occur once, and may appear in any order. Unknown or duplicate keys reject loading. Values cannot contain commas, quotes, tabs, embedded newlines or empty strings. Leading/trailing spaces are trimmed. Comments and blank rows are unsupported. A final newline is allowed.

```csv
key,value
source,Vendor and licensed dataset reference
dataset_id,unique-immutable-export-id
symbol,MNQU26.example
instrument,MNQ
units,contracts
classifier,exchange_aggressor_flag
classifier_details,Exchange field and feed version plus external audit reference
time_basis,UTC
coverage_from_utc,2026-07-06T13:30:00Z
coverage_to_utc,2026-07-06T20:00:00Z
complete,true
rollover_policy,single_contract
contract_id,MNQU26
price_basis,unadjusted
```

`units` accepts only `contracts` or `shares`. For non-futures shares, `contract_id` identifies the actual listed instrument and `single_contract` means that one unchanged instrument series; there is no corporate-action adjustment. UTC timestamps must be exactly `YYYY-MM-DDTHH:MM:SSZ`, valid Gregorian dates from 1971 through 2099, and aligned to five-minute boundaries. Coverage is half-open: `[coverage_from_utc, coverage_to_utc)`. The closing boundary is not another bar opening inside the interval.

Only `rollover_policy=single_contract` and `price_basis=unadjusted` are supported. Select and record the contract before each test. Split research periods at rollover, provide the correct chart history for each contract, and rebuild the previous-session profile using that same contract. V1 refuses adjusted continuous futures chains and automatic stitched-contract rollover. It does not apply a retrospectively chosen rollover schedule or merge volume across contracts. A test window lacking that contract's previous-session data must reject the profile and skip entries.

## Volume-at-price cells

The exact header and an illustrative row are:

```csv
bar_utc,price,buy_volume,sell_volume,unknown_volume
2026-07-06T13:30:00Z,20000.25,100,25,0
```

Rows must be sorted first by UTC bar opening and then by increasing price. Duplicate `(bar_utc,price)` cells reject loading; aggregate them before export. Prices must be positive, within the declared interval and aligned to the selected chart's tick grid. Values use unsigned decimal notation with an optional decimal point and digits on both sides; exponent notation, NaN, infinity, negative values and numeric suffixes are refused. Volumes must be nonnegative and each cell's sum positive. Each individual numeric value is limited to `1e15`; price/tick-size is limited to `1e12`.

The CSV parser uses full-line `FileReadString` reads with explicit line and field-count checks. It deliberately supports a restricted dialect rather than silently accepting malformed general CSV. Numeric-looking garbage such as `10contracts` rejects the entire dataset.

MQL5 file access uses its [file sandbox](https://www.mql5.com/en/docs/files/fileopen): use paths relative to `MQL5/Files`. The Strategy Tester uses each agent's own `MQL5/Files`. Imports named through runtime inputs are not automatically available on every remote/cloud agent. Copy the exact files into the local test agent's sandbox before testing; V1 targets a local single-agent run. Preserve hashes and the identical inputs when reproducing a result.

## Coverage and completion

`Load` checks the declared interval and every record. `Coverage(from_utc,to_utc)` additionally requires a positive-volume imported bar at **every M5 opening** in the requested interval, with no gaps. The declaration `complete,true` alone cannot satisfy coverage. A holiday, lunch halt, missing file fragment or an empty five-minute interval causes a coverage query crossing it to fail. V1 does not encode verified no-trade intervals. Do not fabricate small-volume rows or use zero-volume placeholders to bypass this conservative limitation.

Signal predicates accept exactly one completed interval `[bar_open,bar_open+300)`. A bar is available only at `bar_open+300`; the caller must never issue a signal/profile request whose closing endpoint exceeds the current historically mapped UTC decision time. Merely loading later records does not expose them to an earlier interval query. The main EA gates calls on completed bars and freezes a previous-session profile before the entry window. Coverage for a declared initialization test span must also succeed. Avoid requesting closed-market periods as though they were continuously traded data; when the EA requires continuous coverage across such a span, that dataset is conservatively unsuitable and initialization fails.

The in-memory import limit is 2,000,000 cells. Split long periods by contract/research segment rather than silently truncating. Profile construction allows at most 200,000 contiguous bins.

## Exact experimental predicates

These are stricter mechanical research assumptions, not a claim to reproduce discretionary tape reading. The provider checks volume evidence; the strategy engine separately checks H1 bias, frozen anchors, zone validity, completed OHLC A/B conditions, expiry and session eligibility. A passing imbalance alone is not a trade.

For long **failure bar A**:

1. A's total classified sell volume exceeds its total classified buy volume.
2. A's **lowest traded-price cell** is inside the frozen zone, inclusive of its boundaries. This exact extreme is V1's conservative definition of "near the low".
3. At that cell `sell_volume >= minimum_cell_volume`, `buy_volume > 0`, and `sell_volume / buy_volume >= imbalance_ratio`.
4. A's unknown fraction `unknown / (buy + sell + unknown)` is at most the explicitly selected allowance. Default allowance zero rejects any unknown volume.
5. When explicitly enabled for an MNQ contract dataset, A's total traded contracts meet the selected bar minimum.

For long **retest/opposing-aggression bar B**:

1. The strategy requires B within the next three completed M5 bars, `B.low > A.low`, and `B.close > A.high`, while bias/setup remain valid.
2. B's total classified buy volume exceeds total classified sell volume.
3. At least one B cell **strictly above A.high** has `buy_volume >= minimum_cell_volume`, `sell_volume > 0`, and `buy_volume / sell_volume >= imbalance_ratio`.
4. The same per-bar unknown policy and optional MNQ guard apply to B.

Short predicates mirror these comparisons exactly: A has total buy dominance at its highest traded cell inside the zone with a buy/sell ratio; B has total sell dominance and a sell/buy imbalance strictly below A.low. The strategy checks `B.high < A.high` and `B.close < A.low`. Invalidation takes precedence over any A/B confirmation.

These are **horizontal same-price ratios**. They are not diagonal comparisons between one price's bid volume and a neighboring price's ask volume. Ratio `4.0` is an initial research choice. `minimum_cell_volume` must be explicitly positive; it is measured in the dataset's declared units. A zero denominator is always skipped, even when the numerator is positive. No epsilon, synthetic denominator, infinite imbalance, stacked-imbalance rule, or total-delta-only replacement is used.

## Previous completed cash-session profile

Profile filtering is off in the portable baseline. When enabled it requires the genuine imported volume-at-price data even if the confirmation mode is `PRICE_PROXY`. `TICK_ACTIVITY_PROXY` is not implemented in V1. Bar volume is never distributed over a bar's price range.

The default anchor is the previous completed New York weekday cash session, 09:30 through 16:00 America/New_York. This is an assumption, not the futures trading session. The EA maps historical US DST separately from broker-server offsets and freezes the profile before that day's entry window. The simple weekday calendar does not know exchange holidays or early closes: missing any required five-minute interval rejects that profile. No earlier profile is silently substituted. A holiday-aware exchange calendar would be a separate tested extension.

The provider accepts that completed UTC interval from the clock/session layer. It sums `buy + sell + unknown` at actual traded prices, since an unknown aggressor is still genuine traded volume. It uses **integer positive tick-count bins**, anchored at price zero. A bin with index `k` contains `[k * bin_ticks * tick_size, (k+1) * bin_ticks * tick_size)`. Zero-volume bins between traded bins are included when considering contiguity. There is no auto-selected bin width.

POC is the bin with maximum total volume; ties select the lowest-priced bin. The reported POC is that bin's lower price edge. Start the value area with the POC bin, then repeatedly add whichever immediately adjacent lower/upper bin has greater volume; ties add the lower bin. Continue until included volume is at least 70% of total profile volume. If only one side remains, expand on that side. VAL is the included lowest bin's lower edge; VAH is the included highest bin's **upper exclusive edge**. This algorithm intentionally differs from methods that add two rows per step, rank disconnected price rows, or interpolate boundaries.

A long zone must lie wholly below VAL (`zone_high < VAL`); a short zone wholly above VAH (`zone_low > VAH`). Equality is rejected. Never use the final current-session profile for earlier signals. A frozen profile remains fixed for the NY session even if additional data later become available. Reimporting edited files between runs changes the experiment and requires a new configuration/dataset record.

## Synthetic verification fixtures

Every file under `tests/fixtures` is **hand-authored synthetic input, never market data or market-performance evidence**. The source and contract fields explicitly identify it. Open `scripts/Biltech_OrderFlowTests.mq5` in MetaEditor in its existing project location and compile with F7, preserving the neighboring `Include` directory used by its relative include. Copy the resulting EX5 into the terminal's `MQL5/Scripts` directory and those fixture CSV files to `MQL5/Files/Biltech/fixtures`. Refresh Navigator and run the script on a chart. The script places no orders and uses its explicit synthetic symbol instead of the chart symbol. Read the Journal's pass/fail total; all assertions must pass.

The fixtures exercise mirrored failure/retest evidence, a stronger-ratio rejection, minimum cell/bar volume, price-grid/suffix mismatches, absent data, forbidden classification, malformed numeric input, duplicate cells, missing M5 coverage, strict/explicit unknown policies, and zero-denominator skipping. The full valid fixture aggregates to 450 volume units. With one-tick bins at tick size 0.25, expected POC is 100.25, VAL is 100, and VAH is 101. Restricting the same loaded file to its first completed bar produces POC 100, VAL 100, and VAH 100.5; later records must not affect this result.

Passing these tests establishes behavior on those inputs. It does not authenticate real exchange data, validate discretionary strategy fidelity, establish profitability, or replace a real-tick MT5 execution test. V1 also omits gamma exposure entirely; no gamma data are fabricated.
