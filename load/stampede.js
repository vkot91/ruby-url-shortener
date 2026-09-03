// T061, SC-007, D5 — a hot key expiring must produce one Postgres query, not
// one per request in flight.
//
// Driven by load/stampede.sh, which is what deletes the key and counts what
// Postgres saw. Run it directly only if you have arranged both yourself:
//
//   k6 run -e CODE=<hot code> -e RESULT=load/results/stampede.json load/stampede.js
//
// The edge case behind this is in the spec: a link goes viral, its cache entry
// reaches the end of its life at the moment it is busiest, and every request in
// flight misses simultaneously. Without single-flight that is one Postgres
// query per concurrent request — five hundred here, thousands in production —
// all asking the identical question, at the exact moment the service can least
// afford it. It is the classic way a read cache takes a database down rather
// than protecting it.
//
// The assertion is deliberately not about latency. Losers of the lock wait
// ~10 ms and some fall through to Postgres themselves, so a stampede run is
// *slower* than a steady-state one and should be; what must not happen is 500
// queries.

import http from 'k6/http';
import { Rate, Counter } from 'k6/metrics';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:3001';
const RESULT = __ENV.RESULT || 'load/results/stampede.json';
const CODE = __ENV.CODE;
const EXPECTED = __ENV.EXPECTED;

// The number in D5's statement of the problem: 500 concurrent requests for one
// code whose entry has just gone.
const CONCURRENCY = Number(__ENV.CONCURRENCY || 500);

const correctRedirect = new Rate('correct_redirect');
const wrongDestination = new Counter('wrong_destination');

export const options = {
  discardResponseBodies: true,
  scenarios: {
    stampede: {
      // Every VU starts at once and makes exactly one request, which is what
      // "concurrent" has to mean here. An arrival rate would spread the
      // requests across a second, by which time the winner has long since
      // published and there is no stampede left to observe.
      executor: 'shared-iterations',
      vus: CONCURRENCY,
      iterations: CONCURRENCY,
      maxDuration: '30s',
    },
  },
  thresholds: {
    // Every one of them must still get the right destination. A single-flight
    // that serves some requests a stale or empty answer has not solved the
    // problem, it has moved it.
    correct_redirect: ['rate>0.999'],
    wrong_destination: ['count==0'],
    'http_req_failed': ['rate<0.001'],
  },
  summaryTrendStats: ['min', 'med', 'avg', 'p(90)', 'p(95)', 'p(99)', 'max'],
};

export default function () {
  const response = http.get(`${BASE_URL}/${CODE}`, {
    redirects: 0,
    tags: { name: 'stampede' },
  });

  const ok = response.status === 302 && response.headers['Location'] === EXPECTED;

  correctRedirect.add(ok);

  if (response.status === 302 && response.headers['Location'] !== EXPECTED) {
    wrongDestination.add(1);
  }
}

export function handleSummary(data) {
  const duration = data.metrics['http_req_duration'];

  const lines = [
    '',
    `target     ${BASE_URL}/${CODE}`,
    `concurrent ${CONCURRENCY} requests, one per VU, cache entry deleted immediately before`,
    '',
    `requests   ${value(data.metrics['http_reqs'], 'count', 0)}`,
    `correct    ${(value(data.metrics['correct_redirect'], 'rate', 0) * 100).toFixed(3)}%`,
    `p50 / p99  ${value(duration, 'med', 0).toFixed(1)} ms / ${value(duration, 'p(99)', 0).toFixed(1)} ms`,
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
