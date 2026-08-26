<!--
SYNC IMPACT REPORT
Version change: (uninitialized template) → 1.0.0
Bump rationale: MAJOR-equivalent initial ratification. The file previously contained only
unfilled template placeholders, so this is the first governing version rather than an amendment.

Modified principles: none (no prior principles existed)
Added sections:
  - Core Principles I–V
  - Performance & Reliability Standards
  - Development Workflow
  - Governance
Removed sections: none

Principles derived from: specs/001-url-shortener-mvp/spec.md (notably its "decisions that must be
explainable" list) and the project owner's standing engineering preferences.

Deferred items: none. No TODO placeholders remain.
-->

# URL Shortener Constitution

## Core Principles

### I. The Redirect Path Is Sacred (NON-NEGOTIABLE)

The visitor-facing redirect MUST NOT be blocked by any work that is not required to produce the
redirect itself. Analytics recording, enrichment, logging beyond a single structured line, quota
checks, and billing logic MUST happen outside the visitor's request. The redirect MUST NOT be
rate-limited, throttled, or degraded on the basis of the owning account's plan or usage volume.

Any change that adds a synchronous call to the redirect path MUST be justified in the pull request
with a measurement showing the added latency, and MUST be rejected if it pushes worst-case service
overhead above the standard in Performance & Reliability Standards.

**Rationale**: The clicker is not a customer and did not choose this service. Every millisecond
spent is borrowed from someone who gets nothing in return. Redirect volume is also the product's
network effect, so throttling it to save cost destroys the thing being sold.

### II. Measure Before, Measure After (NON-NEGOTIABLE)

No performance claim enters the repository without a recorded measurement behind it. Any change
made for performance reasons MUST record a before number and an after number, produced by the same
load test on the same reference hardware, committed as data alongside the change.

The naive, cache-free implementation MUST be preserved in a runnable form (a branch, tag, or
feature flag) for as long as the cached path exists, so the comparison can be re-run rather than
merely quoted.

**Rationale**: The difference between the naive and optimised versions is this project's primary
deliverable. An optimisation with no baseline is an opinion.

### III. The Store Enforces Its Own Invariants

Uniqueness, referential integrity, and non-null guarantees MUST be enforced by database constraints,
not by application-level checks. Code MUST NOT implement a check-then-write sequence where a
constraint plus a caught violation would do. Short-code allocation specifically MUST be a single
insert that retries on constraint violation, never a "does this exist?" query followed by an insert.

**Rationale**: Between a check and a write there is a window, and under the concurrency this system
is designed for that window will be hit. A constraint has no window.

### IV. Cache Invalidation Belongs To The Write

Any operation that changes or removes a link MUST invalidate every cached copy of it as part of the
same operation, before the operation is acknowledged to the caller. Time-based expiry MUST NOT be
relied upon to propagate a write. A write path that leaves invalidation to a background job, a
subsequent request, or a TTL is incorrect regardless of whether tests pass.

Cached entries MUST have a bounded memory budget and an eviction policy configured from the first
deployment, and a cached entry's lifetime MUST be refreshed on read so that a hot key cannot expire
at its own traffic peak.

**Rationale**: A user who edits a destination and still sees the old one concludes the product is
broken. This is the single most common defect in systems of this shape and the easiest to prevent
by making invalidation non-optional at the point of write.

### V. The Visitor Is Not The Product

Plain visitor IP addresses MUST NOT be persisted. Where an IP is needed to derive a coarse
attribute such as country, it MUST be consumed and discarded, or reduced to an irreversible
fingerprint salted per day and never retained beyond the window it serves. No cookie, cross-site
identifier, or fingerprinting beyond that MUST be set on the redirect path.

Administrator access to an individual customer's marketing analytics MUST require an explicit
support mode and MUST write an audit record naming who accessed what and why. Routine
administration MUST function without such access.

**Rationale**: Two different people are involved and only one of them agreed to anything. The
clicker consented to nothing, and the paying customer's campaign data is theirs, not the operator's.

## Performance & Reliability Standards

- Service-added redirect overhead MUST stay at or below 50 ms at the 99th percentile under target
  load, measured from request arrival to redirect response.
- At least 95% of redirects MUST be served without a read against the system of record, measured
  over any one-hour window of realistic traffic.
- The system MUST sustain at least 5 000 redirects per second on the project's reference hardware.
- Loss of the cache layer MUST degrade throughput only. It MUST NOT produce redirect errors or
  incorrect destinations, and MUST NOT require operator intervention to recover.
- Repeated requests for codes that do not exist MUST NOT produce repeated load on the system of
  record beyond the first occurrence of each code.
- Losing a bounded window of in-flight click data during a crash is acceptable. Losing links,
  accounts, or the ability to redirect is not. Durability requirements follow that ordering.
- The system of record MUST have backups with point-in-time recovery. The cache MUST be treated as
  reconstructible and MUST NOT hold the only copy of anything.

## Development Workflow

- Work follows Spec-Driven Development in order: `/speckit-specify` → `/speckit-plan` →
  `/speckit-tasks` → `/speckit-implement`. Code MUST NOT be written for a feature whose spec and
  plan are not committed.
- Pull requests are scoped to one user story from the spec, not one task. Each merged pull request
  MUST leave the system in a demonstrable state.
- Every pull request MUST state which functional requirements (FR-xxx) it satisfies and which
  success criteria (SC-xxx) it moves.
- Non-trivial logic MUST arrive with at least one automated test that fails if the logic breaks.
  Test volume is not a goal; a passing suite that would not catch the defect is not coverage.
- All written artifacts — specifications, plans, READMEs, ADRs, code comments, commit messages, and
  pull request bodies — MUST be in English, regardless of the language used in discussion.
- Commits and pushes MUST NOT be made without the project owner's explicit instruction.
- Feature branches follow `<NNN>-<kebab-case-description>` matching the spec directory, or
  `<TICKET-ID>/<kebab-case-description>` when a tracker ticket exists.
- Simplicity is the default. An abstraction with one implementation, configuration for a value that
  never changes, or scaffolding built for an unrequested future MUST be removed in review.

## Governance

This constitution supersedes other practices and conventions in this repository. Where a skill,
template, or generated plan conflicts with it, this document wins.

Amendments MUST be made by editing this file in a dedicated pull request that states the rationale
and the version bump. Versioning is semantic:

- **MAJOR**: a principle is removed, or redefined in a way that invalidates existing compliant work.
- **MINOR**: a principle or section is added, or existing guidance is materially expanded.
- **PATCH**: clarification, wording, or typo fixes with no change in obligation.

Every pull request review MUST verify compliance with the Core Principles. Principles I, II, III,
and IV are objectively checkable and a violation blocks merge. A violation that is nonetheless
intentional MUST be recorded in the pull request with its reasoning and an explicit expiry
condition; an undocumented violation is a defect.

Compliance is reviewed whenever a new feature specification is written, and the Performance &
Reliability Standards are re-validated by the load test before any release.

**Version**: 1.0.0 | **Ratified**: 2026-08-26 | **Last Amended**: 2026-08-26
