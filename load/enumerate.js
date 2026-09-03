// T060, SC-007, D7 — enumeration produces flat Postgres load.
//
//   k6 run -e RESULT=load/results/enumerate.json load/enumerate.js
//
// Somebody walking the code space is ordinary traffic for a shortener, not an
// attack that needs detecting: seven characters of base62 is a small enough
// keyboard that people try. What must not happen is one Postgres query per
// attempt, which is what the naive path does and what would let a single
// process with a `for` loop put the database under more read load than the
// entire legitimate traffic of the service.
//
// The claim being tested is therefore not "absent codes are fast" — they are,
// trivially, because a 404 does less work than a redirect. It is that the
// *database* does not see them. So this script drives absent codes from a small
// repeating pool, and the assertion is made against Postgres' own statement
// counter (`pg_stat_database.xact_commit`), sampled either side of the run by
// load/enumerate.sh, rather than against anything k6 can see from outside.
//
// The pool is small and repeating on purpose. A run using a fresh random code
// every iteration would be measuring the *first* attempt at each of them, and
// every first attempt is a legitimate miss — one query, correctly. Real
// enumeration re-walks the space, and the negative cache is what makes the
// second and subsequent attempts free.

import http from 'k6/http';
import { Rate, Trend } from 'k6/metrics';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:3001';
const RESULT = __ENV.RESULT || 'load/results/enumerate.json';

const RATE = Number(__ENV.RATE || 2000);
const DURATION = Number(__ENV.DURATION || 30);

// Larger than the negative cache would hold by accident, small enough that the
// whole pool is cached within the first second of the run — after which every
// further request for one of these codes must be answered out of Redis.
const POOL_SIZE = 500;

const ALPHABET = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

const pool = buildPool(POOL_SIZE);

const notFound = new Rate('not_found');
const noStore = new Rate('cache_control_no_store');
const enumerateLatency = new Trend('enumerate_latency', true);

export const options = {
  discardResponseBodies: true,
  scenarios: {
    enumerate: {
      executor: 'constant-arrival-rate',
      rate: RATE,
      timeUnit: '1s',
      duration: `${DURATION}s`,
      preAllocatedVUs: Math.min(RATE, 500),
      maxVUs: 2000,
      gracefulStop: '5s',
    },
  },
  thresholds: {
    not_found: ['rate>0.999'],
    cache_control_no_store: ['rate>0.999'],
    // The 404 is served from a string rendered once at boot, so it has no
    // reason to be slower than the redirect it shares a path with.
    'http_req_duration': ['p(99)<50'],
  },
  summaryTrendStats: ['min', 'med', 'avg', 'p(90)', 'p(95)', 'p(99)', 'max'],
};

export default function () {
  const code = pool[Math.floor(Math.random() * pool.length)];

  const response = http.get(`${BASE_URL}/${code}`, {
    redirects: 0,
    tags: { name: 'enumerate' },
  });

  notFound.add(response.status === 404);
  noStore.add(response.headers['Cache-Control'] === 'no-store');
  enumerateLatency.add(response.timings.duration);
}

// Fixed seed, so two runs walk the same codes and a difference between them is
// a difference in the service.
function buildPool(size) {
  const codes = [];

  let state = 20260901;

  for (let index = 0; index < size; index += 1) {
    let code = '';

    for (let character = 0; character < 7; character += 1) {
      state = (state * 1103515245 + 12345) & 0x7fffffff;
      code += ALPHABET[state % ALPHABET.length];
    }

    codes.push(code);
  }

  return codes;
}

export function handleSummary(data) {
  const requests = value(data.metrics['http_reqs'], 'count', 0);

  const lines = [
    '',
    `target     ${BASE_URL}`,
    `offered    ${RATE}/s for ${DURATION}s over a pool of ${POOL_SIZE} absent codes`,
    '',
    `requests   ${requests}`,
    `404 rate   ${(value(data.metrics['not_found'], 'rate', 0) * 100).toFixed(3)}%`,
    `no-store   ${(value(data.metrics['cache_control_no_store'], 'rate', 0) * 100).toFixed(3)}%`,
    `p50 / p99  ${value(data.metrics['http_req_duration'], 'med', 0).toFixed(1)} ms / ${value(data.metrics['http_req_duration'], 'p(99)', 0).toFixed(1)} ms`,
    '',
    `summary written to ${RESULT}`,
    '',
  ];

  return {
    [RESULT]: JSON.stringify(data, null, 2),
    stdout: lines.join('\n'),
  };
}

function value(source, key, fallback) {
  if (source === undefined || source.values === undefined) return fallback;

  const found = source.values[key];

  return found === undefined ? fallback : found;
}
