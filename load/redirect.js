// T041 — the redirect load test. This file is the instrument, and Principle II
// requires it to be reused *unchanged* against the cached build in T059: if the
// script changes between the two runs, the comparison measures the script.
//
//   k6 run -e RESULT=load/results/naive.json load/redirect.js
//
// Run from the repository root, so that `open()` below and the RESULT path both
// resolve. See load/README.md for the reference environment.
//
// Two things here are deliberate and easy to undo by accident:
//
//   * `maxRedirects: 0`. k6 follows redirects by default, which would send
//     every VU out to example.com and measure the internet instead of the
//     service. It also hides the 302, the Location header, and Cache-Control —
//     the three things this request exists to check (contracts/redirect.md).
//   * An open workload (`constant-arrival-rate`), not a closed one. SC-004 is
//     phrased as a rate the service sustains, so the offered rate has to be the
//     independent variable. With a fixed pool of VUs a saturated server simply
//     slows every VU down, throughput flattens, and the number you get back is
//     whatever the server felt like doing rather than whether it kept up.

import http from 'k6/http';
import { Trend, Rate, Counter } from 'k6/metrics';

const corpus = JSON.parse(open('./corpus.json'));

const BASE_URL = __ENV.BASE_URL || 'http://localhost:3001';
const RESULT = __ENV.RESULT || 'load/results/summary.json';

// The offered rates, in requests per second, applied one after another. 5 000
// is SC-004's bar; the steps above it exist so that a build which clears the
// bar still reports how much headroom it has, and the steps below it are where
// a build that cannot clear it reveals what it ran out of.
const STEPS = [500, 1000, 2000, 4000, 6000, 8000];
const STEP_DURATION = 30;
const STEP_GAP = 5;

// Zipf, not uniform (research.md D13). Uniform access across 10 000 links would
// understate the cache in 3C by a factor real traffic never produces — a short
// link's traffic is a handful of posts drawing most of the clicks. s = 1.07 is
// the exponent usually fitted to web popularity; the value matters far less
// than that both runs use the same one.
const ZIPF_EXPONENT = 1.07;

const cumulative = buildZipfCdf(corpus.size, ZIPF_EXPONENT);

// Reported next to the latency numbers because a run whose destinations were
// wrong is not a slower or faster run, it is a broken one (SC-005).
const wrongDestination = new Counter('wrong_destination');
const correctRedirect = new Rate('correct_redirect');
const cacheControlNoStore = new Rate('cache_control_no_store');
const setCookieSeen = new Counter('set_cookie_seen');
const redirectLatency = new Trend('redirect_latency', true);

export const options = {
  discardResponseBodies: true,
  scenarios: scenarios(),
  thresholds: thresholds(),
  // p(99) is SC-001's percentile and k6 does not compute it unless it is asked
  // for here. Naming it in a threshold is not enough: that produces a pass/fail
  // without a number, which is the one thing a baseline may not do.
  summaryTrendStats: ['min', 'med', 'avg', 'p(90)', 'p(95)', 'p(99)', 'max'],
};

export default function () {
  const rank = zipfRank();
  const code = corpus.codes[rank];
  const expected = corpus.destination_pattern.replace('%d', rank);

  const response = http.get(`${BASE_URL}/${code}`, {
    redirects: 0,
    tags: { name: 'redirect' },
  });

  const location = response.headers['Location'];
  const ok = response.status === 302 && location === expected;

  correctRedirect.add(ok);
  redirectLatency.add(response.timings.duration);

  // FR-016: the 302 must not be cacheable, or US3's destination edit fails
  // silently for exactly the visitors who clicked before it.
  cacheControlNoStore.add(response.headers['Cache-Control'] === 'no-store');

  // FR-015 and Principle V. Structural rather than incidental — a cookie here
  // means the session middleware got into the redirect path.
  if (response.headers['Set-Cookie'] !== undefined) {
    setCookieSeen.add(1);
  }

  if (response.status === 302 && location !== expected) {
    wrongDestination.add(1);
  }
}

// One scenario per step rather than one ramping scenario, so that every metric
// carries a `step` tag. The aggregate over a run that degrades is close to
// meaningless — p99 across a healthy 500/s and a collapsed 8 000/s describes
// neither — and the per-step sub-metrics are what name the breaking point.
function scenarios() {
  const built = {};

  STEPS.forEach((rate, index) => {
    built[`step_${rate}`] = {
      executor: 'constant-arrival-rate',
      rate,
      timeUnit: '1s',
      duration: `${STEP_DURATION}s`,
      startTime: `${index * (STEP_DURATION + STEP_GAP)}s`,
      // Sized for the naive path, which holds a VU for the whole of a Postgres
      // round trip. k6 warns rather than fails when it needs more, and the
      // warning itself is a finding.
      preAllocatedVUs: Math.min(rate, 500),
      maxVUs: 4000,
      gracefulStop: `${STEP_GAP}s`,
      tags: { step: String(rate) },
    };
  });

  return built;
}

// Thresholds do double duty in k6: they are pass/fail conditions, and they are
// the only way to make a tagged sub-metric appear in the summary. Every entry
// below is therefore also a line in the committed result file.
function thresholds() {
  const built = {
    // SC-001, SC-005. Not `abortOnFail` — a baseline run is expected to breach
    // these, and the run has to finish so the breach is recorded rather than
    // truncated.
    'http_req_duration{name:redirect}': ['p(99)<50'],
    'http_req_failed{name:redirect}': ['rate<0.001'],
    correct_redirect: ['rate>0.999'],
    cache_control_no_store: ['rate>0.999'],
    wrong_destination: ['count==0'],
    set_cookie_seen: ['count==0'],
  };

  STEPS.forEach((rate) => {
    built[`http_req_duration{step:${rate}}`] = ['p(99)<50'];
    built[`http_req_failed{step:${rate}}`] = ['rate<0.001'];
    built[`http_reqs{step:${rate}}`] = [`count>${rate * STEP_DURATION * 0.99}`];
  });

  return built;
}

// P(rank) ∝ 1/(rank+1)^s, as a cumulative distribution searched per iteration.
// Built once per VU at init: 10 000 doubles is cheaper to hold than a draw is
// to compute analytically, and this way the distribution is inspectable.
function buildZipfCdf(size, exponent) {
  const cdf = new Float64Array(size);

  let total = 0;

  for (let index = 0; index < size; index += 1) {
    total += 1 / Math.pow(index + 1, exponent);
    cdf[index] = total;
  }

  for (let index = 0; index < size; index += 1) {
    cdf[index] /= total;
  }

  return cdf;
}

function zipfRank() {
  const target = Math.random();

  let low = 0;
  let high = cumulative.length - 1;

  while (low < high) {
    const middle = (low + high) >> 1;

    if (cumulative[middle] < target) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }

  return low;
}

// k6's `--out json=` writes one line per metric sample — gigabytes for a run
// this size, and not something anyone can commit or read. The committed result
// is this summary instead: the same numbers, at the granularity the steps above
// give them.
export function handleSummary(data) {
  return {
    [RESULT]: JSON.stringify(data, null, 2),
    stdout: report(data),
  };
}

function report(data) {
  const lines = [''];

  lines.push(`corpus     ${corpus.size} links, seed ${corpus.seed}, zipf s=${ZIPF_EXPONENT}`);
  lines.push(`target     ${BASE_URL}`);
  lines.push('');
  lines.push('  offered  served/s   p50 ms   p99 ms   errors   unserved');

  STEPS.forEach((rate) => {
    const reqs = metric(data, `http_reqs{step:${rate}}`);
    const duration = metric(data, `http_req_duration{step:${rate}}`);
    const failed = metric(data, `http_req_failed{step:${rate}}`);

    const served = value(reqs, 'count', 0) / STEP_DURATION;

    lines.push(
      [
        String(rate).padStart(9),
        // count over the step's own duration. k6's own `rate` field divides by
        // the whole run instead, which for a stepped run understates every step
        // by a factor of six.
        served.toFixed(0).padStart(10),
        value(duration, 'med', 0).toFixed(0).padStart(9),
        value(duration, 'p(99)', 0).toFixed(0).padStart(9),
        `${(value(failed, 'rate', 0) * 100).toFixed(2)}%`.padStart(9),
        // Demand this step asked for and did not get. Derived, because k6's
        // `dropped_iterations` carries no scenario tag — the per-step submetric
        // exists but is always zero, and only the run total is real. The
        // derived column is cross-checked against that total below.
        Math.round(Math.max(0, rate - served) * STEP_DURATION)
          .toString()
          .padStart(11),
      ].join(''),
    );
  });

  const correct = metric(data, 'correct_redirect');
  const wrong = metric(data, 'wrong_destination');
  const cookies = metric(data, 'set_cookie_seen');
  const noStore = metric(data, 'cache_control_no_store');

  lines.push('');
  lines.push(`correct redirects      ${(value(correct, 'rate', 0) * 100).toFixed(3)}%  (${value(correct, 'passes', 0)} checked)`);
  lines.push(`wrong destinations     ${value(wrong, 'count', 0)}`);
  lines.push(`Cache-Control no-store ${(value(noStore, 'rate', 0) * 100).toFixed(3)}%`);
  lines.push(`Set-Cookie seen        ${value(cookies, 'count', 0)}`);
  // k6's own count of iterations it could not start, because every VU it was
  // allowed was still waiting on a response. On an open workload this is the
  // saturation signal, and it should come out close to the derived `unserved`
  // column above — printed together so a disagreement is visible rather than
  // averaged away.
  lines.push(`iterations dropped     ${value(metric(data, 'dropped_iterations'), 'count', 0)}`);
  lines.push('');
  lines.push(`summary written to ${RESULT}`);
  lines.push('');

  return lines.join('\n');
}

function metric(data, name) {
  return data.metrics[name];
}

function value(source, key, fallback) {
  if (source === undefined || source.values === undefined) return fallback;

  const found = source.values[key];

  return found === undefined ? fallback : found;
}
