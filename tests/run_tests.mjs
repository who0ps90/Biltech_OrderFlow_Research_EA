// Portable independent research oracles and source wiring checks.
// This does NOT execute, compile, or backtest MQL5. Run native MQL self-tests too.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
let passed = 0;
let failed = 0;
function test(name, fn) {
  try { fn(); passed++; process.stdout.write(`ok ${passed + failed} - ${name}\n`); }
  catch (error) { failed++; process.stdout.write(`not ok ${passed + failed} - ${name}\n${error.stack}\n`); }
}
const sec = value => Date.parse(value) / 1000;
const near = (actual, expected) => assert.ok(Math.abs(actual - expected) < 1e-9, `${actual} != ${expected}`);
const source = name => fs.readFileSync(path.join(root, name), 'utf8');

// Deliberately independent test oracle: enumerate candidate pivots and gate each
// by the last required right bar's close, not by the pivot's original timestamp.
function availablePivots(bars, wings, decision, kind = 'high') {
  return bars.flatMap((bar, index) => {
    if (index < wings || index + wings >= bars.length) return [];
    const neighbours = bars.slice(index - wings, index + wings + 1).filter((_, i) => i !== wings);
    const strict = neighbours.every(other => kind === 'high' ? bar.high > other.high : bar.low < other.low);
    const confirmed = bars[index + wings].time + 3600;
    return strict && confirmed <= decision ? [{ time: bar.time, confirmed, price: bar[kind] }] : [];
  });
}
function zone(start, end, direction) {
  const distance = Math.abs(end - start);
  const values = [0.705, 0.788, 0.886].map(f => end - direction * f * distance);
  return { low: Math.min(values[0], values[2]), reference: values[1], high: Math.max(values[0], values[2]) };
}
const mirror = (bar, axis = 300) => ({ ...bar, open: axis - bar.open, close: axis - bar.close, high: axis - bar.low, low: axis - bar.high });
function isA(bar, range, direction) {
  return bar.low <= range.high && bar.high >= range.low && direction * (bar.close - bar.open) > 0;
}
function isB(a, b, direction) {
  return direction === 1 ? b.low > a.low && b.close > a.high : b.high < a.high && b.close < a.low;
}
function confirmationDecision({ a, b, range, direction, bias, touch, expiry = 12, window = 3 }) {
  if ((direction === 1 && b.close < range.low) || (direction === -1 && b.close > range.high)) return 'invalidated';
  if (bias !== direction) return 'bias_changed';
  if ((b.time - touch) / 300 >= expiry) return 'expired';
  const age = (b.time - a.time) / 300;
  return age >= 1 && age <= window && isB(a, b, direction) ? 'confirmed' : 'waiting';
}

const pivotBars = [1, 2, 5, 2, 1].map((high, index) => ({ time: 3600 * (index + 1), high, low: -high }));
test('pivot unavailable until the second right H1 bar has closed', () => {
  assert.equal(availablePivots(pivotBars, 2, 21599).length, 0);
  assert.deepEqual(availablePivots(pivotBars, 2, 21600), [{ time: 10800, confirmed: 21600, price: 5 }]);
});
test('equal highs are not strict confirmed pivots', () => {
  const bars = structuredClone(pivotBars); bars[3].high = 5;
  assert.equal(availablePivots(bars, 2, 21600).length, 0);
});
test('mirrored highs produce mirrored lows at the same availability time', () => {
  assert.deepEqual(availablePivots(pivotBars, 2, 21600).map(p => [p.time, p.confirmed]), availablePivots(pivotBars, 2, 21600, 'low').map(p => [p.time, p.confirmed]));
});
test('70.5/78.8/88.6 zone arithmetic and long/short reflection', () => {
  const long = zone(100, 200, 1), short = zone(200, 100, -1);
  near(long.low, 111.4); near(long.reference, 121.2); near(long.high, 129.5);
  near(short.low, 300 - long.high); near(short.high, 300 - long.low); near(short.reference, 300 - long.reference);
});
const longRange = zone(100, 200, 1);
const a = { time: 3000, open: 117, low: 115, high: 132, close: 128 };
const b = { time: 3900, open: 128, low: 116, high: 137, close: 134 };
test('long A/B evidence mirrors exactly for shorts', () => {
  assert.equal(isA(a, longRange, 1), true); assert.equal(isB(a, b, 1), true);
  const shortRange = zone(200, 100, -1);
  assert.equal(isA(mirror(a), shortRange, -1), true); assert.equal(isB(mirror(a), mirror(b), -1), true);
});
test('doji A and equal B low/high fail strict confirmation', () => {
  assert.equal(isA({ ...a, close: a.open }, longRange, 1), false);
  assert.equal(isB(a, { ...b, low: a.low }, 1), false);
  assert.equal(isB(a, { ...b, close: a.high }, 1), false);
  assert.equal(isB(mirror(a), mirror({ ...b, low: a.low }), -1), false);
});
test('third next M5 slot confirms and the fourth cannot', () => {
  const decision = { a, b, range: longRange, direction: 1, bias: 1, touch: a.time };
  assert.equal(confirmationDecision(decision), 'confirmed');
  assert.equal(confirmationDecision({ ...decision, b: { ...b, time: 4200 } }), 'waiting');
});
test('missing bars consume elapsed confirmation slots', () => {
  assert.equal(confirmationDecision({ a, b: { ...b, time: a.time + 1500 }, range: longRange, direction: 1, bias: 1, touch: a.time }), 'waiting');
});
test('boundary invalidation, changed bias and expiry take precedence over B', () => {
  const args = { a, b, range: longRange, direction: 1, bias: 1, touch: a.time };
  assert.equal(confirmationDecision({ ...args, range: { low: 135, high: 140 } }), 'invalidated');
  assert.equal(confirmationDecision({ ...args, bias: 0 }), 'bias_changed');
  assert.equal(confirmationDecision({ ...args, touch: b.time - 3600 }), 'expired');
});
test('close exactly on 88.6 boundary is not beyond it', () => {
  const value = confirmationDecision({ a, b: { ...b, close: longRange.low }, range: longRange, direction: 1, bias: 1, touch: a.time });
  assert.equal(value, 'waiting');
});

// IANA Intl is a separate timezone implementation from the MQL US-DST formula.
const nyFormat = new Intl.DateTimeFormat('en-GB', { timeZone: 'America/New_York', hour: '2-digit', minute: '2-digit', hourCycle: 'h23', weekday: 'short' });
function nyParts(utc) { return Object.fromEntries(nyFormat.formatToParts(new Date(utc)).map(p => [p.type, p.value])); }
function inNyWindow(utc) {
  const parts = nyParts(utc), minutes = Number(parts.hour) * 60 + Number(parts.minute);
  return !['Sat', 'Sun'].includes(parts.weekday) && minutes >= 570 && minutes < 660;
}
test('modern spring DST changes the UTC cash opening', () => {
  assert.equal(inNyWindow('2026-03-06T14:30:00Z'), true);
  assert.equal(inNyWindow('2026-03-09T13:29:59Z'), false);
  assert.equal(inNyWindow('2026-03-09T13:30:00Z'), true);
  assert.equal(nyParts('2026-03-09T13:30:00Z').hour, '09');
});
test('modern autumn DST and midnight Malaysia display', () => {
  assert.equal(inNyWindow('2026-11-02T14:30:00Z'), true);
  assert.equal(inNyWindow('2026-11-02T15:59:59Z'), true);
  assert.equal(inNyWindow('2026-11-02T16:00:00Z'), false);
  const malaysia = new Intl.DateTimeFormat('en-GB', { timeZone: 'Asia/Kuala_Lumpur', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' });
  assert.equal(malaysia.format(new Date('2026-11-02T16:00:00Z')), '00:00');
});
test('pre-2007 US DST differs from modern March rule', () => {
  assert.equal(nyParts('2006-03-20T14:30:00Z').hour, '09');
  assert.equal(nyParts('2006-04-03T13:30:00Z').hour, '09');
});
test('weekend and exclusive session endpoint reject entry', () => {
  assert.equal(inNyWindow('2026-10-24T13:30:00Z'), false);
  assert.equal(inNyWindow('2026-10-23T15:00:00Z'), false);
});
function mapServer(server, periods) {
  const candidates = periods.map(p => server - p.offset * 60).filter((utc, i) => utc >= periods[i].from && utc < periods[i].to);
  if (candidates.length !== 1) throw new Error(candidates.length ? 'ambiguous' : 'unmapped');
  return candidates[0];
}
const change = sec('2026-03-29T01:00:00Z');
test('historical server offset uses the interval applicable at that date', () => {
  const periods = [{ from: change - 86400, to: change, offset: 120 }, { from: change, to: change + 86400, offset: 180 }];
  assert.equal(mapServer(change - 3600 + 120 * 60, periods), change - 3600);
  assert.equal(mapServer(change + 3600 + 180 * 60, periods), change + 3600);
  assert.throws(() => mapServer(change + 150 * 60, periods), /unmapped/);
});
test('server fallback repeated clock hour rejects ambiguity', () => {
  const periods = [{ from: change - 86400, to: change, offset: 180 }, { from: change, to: change + 86400, offset: 120 }];
  assert.throws(() => mapServer(change + 150 * 60, periods), /ambiguous/);
});
test('schedule coverage is half open at the final endpoint', () => {
  assert.throws(() => mapServer(change + 86400 + 120 * 60, [{ from: change, to: change + 86400, offset: 120 }]), /unmapped/);
});

// Brute-force feasible lot grid is independent from production downward rounding.
function largestFeasible({ equity, percent, min, max, step, loss, margin, freeMargin }) {
  const budget = equity * percent / 100;
  let chosen = 0;
  for (let index = 0; index <= Math.round((max - min) / step); index++) {
    const volume = Math.round((min + index * step) * 1e8) / 1e8;
    if (loss(volume) <= budget + 1e-10 && margin(volume) <= freeMargin) chosen = volume;
  }
  return chosen;
}
test('different contract economics and account-currency conversion change sizing', () => {
  const common = { equity: 10000, percent: 0.25, min: 0.1, max: 10, step: 0.1, margin: lot => lot * 100, freeMargin: 10000 };
  near(largestFeasible({ ...common, loss: lot => 20 * 2 * lot }), 0.6);
  near(largestFeasible({ ...common, loss: lot => 20 * 20 * lot }), 0);
  near(largestFeasible({ ...common, loss: lot => 20 * 2 * 4.2 * lot }), 0.1);
});
test('commission and adverse execution reduce feasible size, minimum lot can reject', () => {
  const common = { equity: 10000, percent: 0.25, min: 0.1, max: 2, step: 0.1, margin: lot => lot * 100, freeMargin: 1000 };
  near(largestFeasible({ ...common, loss: lot => (40 + 10) * lot }), 0.5);
  near(largestFeasible({ ...common, min: 1, step: 1, loss: lot => 40 * lot }), 0);
});
test('margin constraint can reduce size without being mistaken for loss risk', () => {
  near(largestFeasible({ equity: 10000, percent: 0.25, min: 0.1, max: 2, step: 0.1, loss: lot => 10 * lot, margin: lot => 1000 * lot, freeMargin: 250 }), 0.2);
});
test('tick size differs from point and stops round outward', () => {
  const tick = 0.25, point = 0.01, desiredStop = 99.13;
  near(Math.floor(desiredStop / tick) * tick, 99);
  near(Math.ceil(desiredStop / tick) * tick, 99.25);
  assert.notEqual(tick, point);
});
test('spread greater than ten percent of planned stop rejects', () => {
  const permitted = (spread, distance) => distance > 0 && spread / distance <= 0.10;
  assert.equal(permitted(1, 10), true); assert.equal(permitted(1.01, 10), false); assert.equal(permitted(1, 0), false);
});

class ExecutionLedger {
  constructor(snapshot) { this.seen = new Set(snapshot?.seen ?? []); this.consumed = new Set(snapshot?.consumed ?? []); this.entries = snapshot?.entries ?? 0; }
  confirm(id) { if (this.consumed.has(id)) return false; this.consumed.add(id); return true; }
  entry(deal) { if (!this.seen.has(deal)) { this.seen.add(deal); this.entries++; } }
  snapshot() { return { seen: [...this.seen], consumed: [...this.consumed], entries: this.entries }; }
}
test('confirmed setup stays consumed after a rejected order and restart', () => {
  let ledger = new ExecutionLedger(); assert.equal(ledger.confirm('long_1_2'), true);
  // No fill is recorded for rejection. Persist the consumed setup before send.
  ledger = new ExecutionLedger(ledger.snapshot());
  assert.equal(ledger.confirm('long_1_2'), false); assert.equal(ledger.entries, 0);
});
test('duplicate entry deals after restart do not increase the session count', () => {
  let ledger = new ExecutionLedger(); ledger.entry(123); ledger.entry(123);
  ledger = new ExecutionLedger(ledger.snapshot()); ledger.entry(123); ledger.entry(124);
  assert.equal(ledger.entries, 2);
});
test('two losses, two entries or 0.50 percent session equity drawdown stop entries', () => {
  const blocked = ({ entries = 0, losses = 0, equity = 10000, baseline = 10000 }) => entries >= 2 || losses >= 2 || equity <= baseline * 0.995;
  assert.equal(blocked({}), false); assert.equal(blocked({ entries: 2 }), true);
  assert.equal(blocked({ losses: 2 }), true); assert.equal(blocked({ equity: 9950 }), true); assert.equal(blocked({ equity: 9950.01 }), false);
});
test('forced closure waits for first available tick at or after the boundary', () => {
  const end = sec('2026-10-23T15:00:00Z');
  const ticks = [end - 1, end + 17, end + 21];
  assert.equal(ticks.find(tick => tick >= end), end + 17);
});
test('OHLC with both exits inside the range has no unique event ordering', () => {
  const bar = { open: 100, high: 110, low: 90, close: 102 }, stop = 95, target = 105;
  assert.equal(bar.low <= stop && bar.high >= target, true);
  const stopFirst = [100, 95, 90, 110, 105, 102], targetFirst = [100, 105, 110, 90, 95, 102];
  assert.notDeepEqual(stopFirst, targetFirst);
  assert.equal(Math.min(...stopFirst), Math.min(...targetFirst));
  assert.equal(Math.min(...stopFirst), bar.low); assert.equal(Math.max(...targetFirst), bar.high);
});

function readCells(filename, tick = 0.25) {
  const lines = source(`tests/fixtures/${filename}`).trim().split(/\r?\n/);
  assert.equal(lines.shift(), 'bar_utc,price,buy_volume,sell_volume,unknown_volume');
  const keys = new Set();
  return lines.map(line => {
    const fields = line.split(','); assert.equal(fields.length, 5);
    assert.match(fields[0], /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/);
    fields.slice(1).forEach(value => assert.match(value, /^\d+(?:\.\d+)?$/));
    const [price, buy, sell, unknown] = fields.slice(1).map(Number);
    const time = sec(fields[0]);
    assert.ok(Number.isFinite(time) && time % 300 === 0);
    assert.ok(price > 0 && buy + sell + unknown > 0);
    near(price / tick, Math.round(price / tick));
    const key = `${time}/${price}`; assert.ok(!keys.has(key), 'duplicate cell'); keys.add(key);
    return { time, price, buy, sell, unknown };
  });
}
function profileOracle(cells, from, to, tick = 0.25) {
  const buckets = new Map();
  for (const cell of cells.filter(c => c.time >= from && c.time < to)) {
    const bin = Math.round(cell.price / tick);
    buckets.set(bin, (buckets.get(bin) ?? 0) + cell.buy + cell.sell + cell.unknown);
  }
  const total = [...buckets.values()].reduce((sum, volume) => sum + volume, 0);
  const ranked = [...buckets].sort((a, b) => b[1] - a[1] || a[0] - b[0]);
  const poc = ranked[0][0]; let low = poc, high = poc, included = buckets.get(poc);
  const min = Math.min(...buckets.keys()), max = Math.max(...buckets.keys());
  while (included < 0.7 * total) {
    const lower = low > min ? buckets.get(low - 1) ?? 0 : -1;
    const upper = high < max ? buckets.get(high + 1) ?? 0 : -1;
    if (lower >= upper) { low--; included += lower; } else { high++; included += upper; }
  }
  return { poc: poc * tick, val: low * tick, vah: (high + 1) * tick, total };
}
test('synthetic profile sums real cells and applies deterministic POC/value-area ties', () => {
  const profile = profileOracle(readCells('valid_cells.csv'), sec('2026-07-06T13:30:00Z'), sec('2026-07-06T13:50:00Z'));
  assert.deepEqual(profile, { poc: 100.25, val: 100, vah: 101, total: 450 });
});
test('future cells cannot change an earlier completed profile query', () => {
  const from = sec('2026-07-06T13:30:00Z'), to = from + 300;
  const cells = readCells('valid_cells.csv');
  const earlier = profileOracle(cells, from, to);
  assert.deepEqual(earlier, { poc: 100, val: 100, vah: 100.5, total: 110 });
  assert.deepEqual(earlier, profileOracle(cells.filter(cell => cell.time < to), from, to));
});
test('missing exchange bars are distinct from verified complete coverage', () => {
  const from = sec('2026-07-06T13:30:00Z'), times = new Set(readCells('missing_bar_cells.csv').map(cell => cell.time));
  assert.equal([from, from + 300, from + 600].every(time => times.has(time)), false);
});
test('malformed numerics, duplicate cells and off-tick prices reject independently', () => {
  for (const filename of ['malformed_cells.csv', 'duplicate_cells.csv', 'off_tick_cells.csv']) assert.throws(() => readCells(filename));
});
test('unknown classifications stay in the total and strict default rejects them', () => {
  const cells = readCells('unknown_cells.csv').filter(cell => cell.time === sec('2026-07-06T13:30:00Z'));
  const unknown = cells.reduce((sum, cell) => sum + cell.unknown, 0);
  const total = cells.reduce((sum, cell) => sum + cell.buy + cell.sell + cell.unknown, 0);
  assert.ok(unknown > 0 && unknown / total <= 0.2);
  assert.equal(unknown / total <= 0, false);
});
test('zero denominator is not treated as infinite imbalance', () => {
  const cells = readCells('zero_denominator_cells.csv');
  const extreme = cells.filter(cell => cell.time === sec('2026-07-06T13:30:00Z')).sort((a, b) => a.price - b.price)[0];
  assert.equal(extreme.buy, 0); assert.ok(extreme.sell > 0);
  assert.equal(extreme.buy > 0 && extreme.sell / extreme.buy >= 4, false);
});

test('MQL strategy wires completed-bar and duplicate guards before signal processing', () => {
  const code = source('Include/Biltech/Strategy.mqh');
  assert.match(code, /bar\.time\+300>decision/);
  assert.match(code, /bar\.time<=m_last_bar/);
  assert.match(code, /h1\[i\+m_side\]\.time\+3600/);
  assert.match(code, /bar\.time<setup\.armed/);
});
test('MQL invalidation and expiry precede confirmation and retire consumed setups', () => {
  const code = source('Include/Biltech/Strategy.mqh');
  const evaluate = code.slice(code.indexOf('bool Evaluate('));
  assert.ok(evaluate.indexOf('INVALID_CLOSE_BEYOND_886') < evaluate.indexOf('PRICE_PROXY_B_CONFIRMED'));
  assert.ok(evaluate.indexOf('INVALID_BIAS_CHANGED') < evaluate.indexOf('PRICE_PROXY_B_CONFIRMED'));
  assert.ok(evaluate.indexOf('EXPIRED_AFTER_FIRST_TOUCH') < evaluate.indexOf('PRICE_PROXY_B_CONFIRMED'));
  assert.match(evaluate, /setup\.consumed=true;\s*Retire\(setup\)/);
});
test('MQL clock rejects ambiguity and does not call present offset APIs', () => {
  const code = source('Include/Biltech/Clock.mqh').replace(/\/\/[^\n]*/g, '');
  assert.match(code, /matches!=1/); assert.match(code, /AMBIGUOUS_BROKER_SERVER_TIME/);
  assert.match(code, /period\.from_utc!=m_periods\[n-1\]\.to_utc/);
  assert.doesNotMatch(code, /\b(?:TimeGMTOffset|TimeDaylightSavings)\s*\(/);
  assert.match(code, /dt\.year<1987/);
});
test('MQL provider rejects unsupported classification, sparse coverage and zero denominator', () => {
  const code = source('Include/Biltech/OrderFlow.mqh');
  assert.match(code, /exchange_aggressor_flag/); assert.match(code, /quote_match_at_trade/);
  assert.match(code, /denominator<=0\.0/);
  assert.match(code, /instrument MNQ with units contracts/);
  assert.match(code, /Profile\(datetime from_utc,datetime to_utc/);
  assert.match(code, /if\(!Coverage\(from_utc,to_utc,reason\)\)/);
});
test('MQL risk uses symbol profit/margin functions and downward volume rounding', () => {
  const code = source('Include/Biltech/Execution.mqh');
  assert.match(code, /OrderCalcProfit\(/); assert.match(code, /OrderCalcMargin\(/);
  assert.match(code, /MathFloor\(MathMin\(vmax,budget\/plan\.risk_per_lot\)\/step/);
  assert.match(code, /ROUNDED_VOLUME_EXCEEDS_RISK/); assert.match(code, /MINIMUM_VOLUME_EXCEEDS_RISK/);
  assert.match(code, /0\.10\*distance/); assert.match(code, /SYMBOL_TRADE_TICK_SIZE/);
});
test('all presets cover every current input and keep both explicit safety acknowledgments false', () => {
  const inputs = [...source('Biltech_OrderFlow_Research_EA.mq5').matchAll(/^input\s+(?!group\b)\w+\s+(Inp\w+)\s*=/gm)].map(match => match[1]).sort();
  const files = fs.readdirSync(path.join(root, 'config')).filter(file => file.endsWith('.set'));
  assert.ok(files.length >= 3);
  for (const file of files) {
    const settings = Object.fromEntries(source(`config/${file}`).split(/\r?\n/).filter(line => line && !line.startsWith(';')).map(line => {
      const index = line.indexOf('='); return [line.slice(0, index), line.slice(index + 1)];
    }));
    assert.deepEqual(Object.keys(settings).sort(), inputs, `${file}: preset input drift`);
    assert.equal(settings.InpAllowLiveTrading, 'false'); assert.equal(settings.InpBrokerClockAcknowledged, 'false');
    assert.equal(settings.InpEnableMNQMinimumVolume, 'false');
  }
});
test('MQL main persists consumed signal and submission lock before sending', () => {
  const code = source('Biltech_OrderFlow_Research_EA.mq5');
  assert.match(code, /!tester\s*&&\s*!InpAllowLiveTrading/);
  assert.match(code, /if\(!InpBrokerClockAcknowledged\)/);
  assert.match(code, /g_state\.uncertain=true/);
  const start = code.indexOf('g_state.uncertain=true');
  assert.ok(code.indexOf('if(!Persist())', start) < code.indexOf('g_execution.Send(', start));
  assert.match(code, /MISSED_HISTORICAL_B_NO_RETROSPECTIVE_ENTRY/);
  assert.match(code, /InpExportCSV\s*&&\s*!MQLInfoInteger\(MQL_OPTIMIZATION\)/);
});
test('all exported audit columns are documented and timestamp domains are explicit', () => {
  const code = source('Include/Biltech/Audit.mqh'), documentation = source('docs/CSV_SCHEMA.md');
  const header = code.match(/FileWriteString\(m_file,"(event,[^"]+)\\r\\n"\)/)?.[1];
  assert.ok(header, 'audit header not found');
  const columns = header.split(',');
  assert.equal(columns.length, 63); assert.equal(new Set(columns).size, 63);
  for (const column of columns) assert.ok(documentation.includes(`\`${column}\``), `undocumented column: ${column}`);
  assert.ok(columns.includes('b_utc') && columns.includes('anchor_start_confirmed_utc'));
});

process.stdout.write(`\n${passed} passed, ${failed} failed. Portable independent oracles/source checks only; no MQL execution or backtest.\n`);
process.exitCode = failed ? 1 : 0;
