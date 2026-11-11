# Deterministic research specification

This document separates the supplied discretionary description from the mechanical assumptions implemented for repeatable testing. The first referenced video is [PL7LKUsCgIQ](https://www.youtube.com/watch?v=PL7LKUsCgIQ); the user's supplied description, rather than an independently obtained transcript, provides the source-described rules below. The inaccessible second video is excluded.

## Source-described framework

Higher-timeframe context, a pullback around 70.5%, 78.8% and 88.6% retracements, a location outside selected profile value, failed aggressive participation, renewed opposing participation, a stop beyond the failure area and prior swing targets form the discretionary framework. The 4:1 footprint display and 20,000-contract M5 MNQ threshold are source-described settings. Gamma and discretionary trade management are material parts that are not reproduced in V1.

## Mechanical assumptions shared by both modes

| Item | Implemented baseline assumption |
| --- | --- |
| Signal data | Completed H1 context and M5 setup bars; current chart symbol |
| Pivots | Strict high/low against two completed bars on each side by default; ties are not pivots |
| Availability | Pivot timestamp is the H1 bar open; confirmation timestamp is the final required right-side H1 bar open plus one hour |
| Bullish bias | Latest two confirmed highs and latest two confirmed lows are each strictly higher |
| Bearish bias | Both pairs are strictly lower; mixed/tied/insufficient structure is neutral |
| Long impulse | Search confirmed highs newest first; pair the newest eligible end high with the latest strictly earlier confirmed low whose price is lower |
| Short impulse | Mirrored: newest eligible end low, latest strictly earlier confirmed higher high |
| Active setup | Freeze anchors, confirmation times, direction, zone and ID when armed; do not replace anchors during that setup |
| Setup identity | Direction plus start/end pivot timestamps; runtime namespace additionally distinguishes symbol/magic/configuration |
| One attempt | A valid B consumes the setup before execution checks; rejection does not re-arm that impulse |
| Entry | First received tradable tick after B has closed, subject to every risk/session/data/execution guard |

Impulse eligibility requires both anchors to be available at the decision timestamp. A setup's arming decision cannot retrospectively treat the bar just completed before arming as A or B. An active setup stays frozen even when newer same-direction pivots appear; changed or neutral bias invalidates it. Retired setups cannot be reused. A cold start begins at the latest completed bar. A restart restores the journal then catches up at most 512 M5 bars without placing historical orders; only B on the latest completed bar may attempt entry. Longer gaps retire a potentially stale active setup.

For long anchors `L < H`, the zone is `[H − 0.886(H−L), H − 0.705(H−L)]`; 78.8% is a reference. For short anchors `H > L`, use `[L + 0.705(H−L), L + 0.886(H−L)]`. Bar/zone intersection includes equality.

On each new completed M5 bar the precedence is: invalid/missing context; close beyond the 88.6% boundary; changed/neutral bias; expiry; B; a possible new A. A long close strictly below the zone's lower boundary invalidates; a short close strictly above its upper boundary invalidates. Equality alone does not invalidate. Expiry begins at the first bar that intersects the zone, even if that bar does not qualify as A. At elapsed slot 12 the default setup expires. Slots are `(current M5 open − first touch open)/300`, so missing M5 slots consume time. Invalidation and expiry prevent entry even if confirmation otherwise passes.

## PRICE_PROXY confirmation

This mode is a two-stage **price rejection** assumption, not evidence of actual absorption or aggressor flow.

For a long, A intersects the zone and closes strictly above its open. Keep the earliest A; do not replace it with a newer candidate while its confirmation window remains open. Within the next three M5 time slots, B must have `B.low > A.low` and `B.close > A.high`. The third slot is included; A's own bar and the fourth slot cannot confirm. Bias and setup validity must still pass. After A's window expires, the current bar may become a new A if it qualifies and the setup remains valid. First-touch expiry does not restart with a new A.

For a short, A closes strictly below its open; B must have `B.high < A.high` and `B.close < A.low`. The same timing and replacement rules apply. Doji A bars and equal highs/lows/closes do not pass strict confirmation.

## Stop, target and costs

The long stop is below A's low and the short stop above A's high, buffered by the larger of the configured minimum number of symbol ticks and `0.10 × ATR(14)`. V1 defines ATR as the arithmetic mean of the last 14 completed M5 true ranges (each true range includes the previous close), rather than Wilder smoothing. Stops round outward to tick size. Invalid geometry, broker stop/freeze constraints, excessive distance, oversized spread, insufficient margin or a minimum lot above the risk budget skip the attempt.

The default target is the frozen impulse high for longs or low for shorts. Optional fixed-R targeting solves for at least 1.5 net R after the configured estimated costs, rounding the target outward; it is not simply 1.5 times raw price distance when costs are nonzero. Prospective reward/risk after configured estimated costs must be at least 1.5. Estimated costs screen and size orders; MT5's actual commission/fee/swap determine realized outcomes. Break-even, partial profit-taking and trailing variants are not implemented in V1. Broker partial fills and partial exit accounting are execution handling, not a discretionary management variant.

The default equity risk budget is 0.25% per entry, using actual planned entry/stop distance, symbol-specific `OrderCalcProfit`, account currency and volume step. Round volume downward, include configured adverse-execution/commission assumptions and verify margin separately. The risk budget is not a guaranteed maximum loss: slippage, gaps, costs and failed broker requests can exceed it.

## Session and portfolio controls

New entries are allowed only on New York weekdays from 09:30 inclusive to 11:00 exclusive. The broker-offset CSV supplies historical server/UTC mapping, and US DST rules cover 1987 onward. [NIST documents the US DST rules in effect since 2007](https://www.nist.gov/pml/time-and-frequency-division/popular-links/daylight-saving-time-dst). This is a weekday cash-window model without a holiday/early-close calendar. `ForceFlatAtSessionEnd` defaults true and is a research assumption; its request executes on the first available tick at or after the end. Tick absence, rejected closes and an indeterminate close-request outcome can delay liquidation. Close intent is persisted before submission; unknown outcomes remain locked until exact-order/position evidence permits another request.

One EA position at a time, at most two successful entry orders per New York session, at most two consecutive losing completed positions and a 0.50% session equity drawdown gate constrain new trades. A flat/positive completed trade resets the loss sequence. Equity baseline is the first tradable tick at/after 09:30, only if a pre-open tick was observed that day; a cold mid-session start blocks the day. Drawdown is against that fixed baseline and latches the session off. Durable state preserves these limits across restarts, and completed-position results/entry counts are reconstructed from executed history. See the README for recovery and uncertain-order details. No martingale, grid, averaging down or stop widening is implemented. Other positions and account cash flows can still affect equity and margin, so use an isolated account/tester context.

## Optional profile and EXCHANGE_ORDERFLOW

Profile filtering defaults off. V1 supports genuine imported traded-volume profiles, including when used as a filter with price-proxy confirmation. It does not implement a tick-activity profile variant. Such a future variant would have to be explicitly named `TICK_ACTIVITY_PROXY` and tested separately.

When enabled, the profile uses the previous completed weekday New York 09:30–16:00 cash session. Its complete imported data must already be available; no final current-session profile is used retrospectively. The long zone must be wholly below VAL and the short zone wholly above VAH. Profile anchoring and the choice of weekday calendar are research assumptions. Bin size, POC tie-breaking, value-area expansion, rollover restrictions and exact exchange-mode failure/retest/opposition rules are specified in [ORDERFLOW_DATA.md](ORDERFLOW_DATA.md).

Exchange mode requires genuine imported volume-at-price with documented aggressor classification and explicit unknown volume. It uses no candle/tick-direction classifier and never falls back to proxy mode when data are absent. Its deterministic predicates are research assumptions, not proof of discretionary absorption. The optional 20,000-contract minimum requires explicit matching MNQ data and units; it remains disabled otherwise. Gamma is omitted.
