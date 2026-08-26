# Feature Specification: URL Shortener MVP

**Feature Branch**: `001-url-shortener-mvp`

**Created**: 2026-08-26

**Status**: Draft

**Input**: User description: (link shortener: free unlimited redirects, paid brand + analytics; read-skewed system where redirects are served from cache; three roles — link creator, anonymous clicker, platform administrator; first version scoped to registration, auto-code link creation, cached redirect, click counter, dashboard list, destination editing, deletion, basic admin with ban, and a load test)

## Scope Note

The source description covers the full product vision (pricing tiers, custom domains, teams, deep analytics, webhooks, QR, public API, SSO). **This specification covers only the first version** as bounded by the author in section 9 of the description. Everything else is recorded under Out of Scope so it is not lost, but it is not specified here.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Shorten a link and share it (Priority: P1)

A marketer signs up, pastes a long destination address into their dashboard, and receives a short address they can copy with one click. They paste it into a social post. Anyone who taps that post lands on the intended destination without noticing an intermediary.

**Why this priority**: This is the entire product in one slice. Without it nothing else has a reason to exist, and with it alone the service is already usable.

**Independent Test**: Register an account, create one link, open the short address in a fresh browser, and confirm arrival at the destination. Delivers the core value with no other story implemented.

**Acceptance Scenarios**:

1. **Given** a registered signed-in creator, **When** they submit a valid destination address, **Then** the system returns a short address containing a 7-character random code and offers one-click copy.
2. **Given** a published short address, **When** an anonymous visitor opens it, **Then** they are redirected to the destination address.
3. **Given** a destination address that is malformed, uses a scheme other than http/https, points at the service's own short-link space, or resolves to a private/internal network address, **When** the creator submits it, **Then** creation is rejected with a message naming the reason and no link is created.
4. **Given** a destination on the platform's blocked-domain list, **When** the creator submits it, **Then** creation is rejected.
5. **Given** two different creators submitting the identical destination address, **When** both create links, **Then** two separate links with different codes exist, each with its own owner and its own statistics.
6. **Given** a creator who has reached the free limit of 50 links, **When** they try to create another, **Then** creation is refused with an explanation of the limit.
7. **Given** a creator who has created links at an abusive rate within the last hour, **When** they try to create another, **Then** creation is refused until the window resets, while all existing redirects continue to work.

---

### User Story 2 - See whether the post worked (Priority: P2)

The creator returns a day later and wants one number: how many people opened the link. They see their links listed with a click count against each.

**Why this priority**: The counter is what converts a one-off tool into something people come back to. It is worthless without US1 but makes US1 worth repeating.

**Independent Test**: Create a link, open it a known number of times, and confirm the dashboard reports that count within the stated freshness window.

**Acceptance Scenarios**:

1. **Given** a link opened N times, **When** the creator views their dashboard, **Then** the click count for that link reflects all N opens within 30 seconds of the last one.
2. **Given** a signed-in creator, **When** they open their dashboard, **Then** they see only their own links and only their own counts.
3. **Given** a creator viewing their dashboard, **When** the list is displayed, **Then** each row shows the short address, the destination, the creation date, and the click count.
4. **Given** a redirect is being served, **When** the click is recorded, **Then** recording does not delay the visitor's redirect response.
5. **Given** the click-recording pipeline is unavailable, **When** visitors open links, **Then** redirects continue to succeed and only statistics are affected.

---

### User Story 3 - Fix a mistake without reprinting the poster (Priority: P3)

The creator spots a typo in the destination. They edit where the link points; the short address itself stays exactly as published. They can also remove a link that has served its purpose.

**Why this priority**: This is the reason a short link beats a raw address. It is not needed to prove the concept, but the product is not credible without it.

**Independent Test**: Create a link, open it once, change its destination, open it again, and confirm the second open lands on the new destination.

**Acceptance Scenarios**:

1. **Given** an existing link, **When** its owner changes the destination address, **Then** the short code is unchanged and the very next visitor is sent to the new destination — no stale destination is ever served after the change is confirmed.
2. **Given** an existing link, **When** its owner attempts to change the short code itself, **Then** the system does not permit it and explains that a different code means a new link.
3. **Given** an existing link, **When** its owner deletes it, **Then** visitors thereafter receive the not-found page, the link disappears from the active dashboard list, and its accumulated statistics are retained.
4. **Given** a deleted link, **When** any creator attempts to claim its code as a custom code, **Then** the code remains unavailable for 30 days after deletion.
5. **Given** a link owned by creator A, **When** creator B attempts to view, edit, or delete it, **Then** the request is refused as if the link did not exist for them.

---

### User Story 4 - Keep the platform clean (Priority: P4)

The administrator opens the admin area each morning, finds links reported as harmful, and bans them. They can also ban every link belonging to an abusive account.

**Why this priority**: A shortener without moderation becomes a phishing tool within weeks. Not needed to demonstrate the core, mandatory before anything is public.

**Independent Test**: Report a link, find it in the admin queue, ban it, and confirm visitors now see the warning page instead of a redirect.

**Acceptance Scenarios**:

1. **Given** an administrator, **When** they search by short code or by destination address, **Then** they find the matching link regardless of who owns it.
2. **Given** a link the administrator bans, **When** a visitor opens it, **Then** they see a safety warning page instead of being redirected, and the ban takes effect for the next visitor with no stale redirect.
3. **Given** an account the administrator bans, **When** visitors open any of that account's links, **Then** all of them show the warning page.
4. **Given** a visitor on a warning page, **When** they use the report control, **Then** the report enters the administrator's queue.
5. **Given** a non-administrator, **When** they attempt to reach any admin function, **Then** access is refused.
6. **Given** an administrator in normal operation, **When** they use the admin area, **Then** no creator's marketing statistics are exposed to them.

---

### Edge Cases

- **Code does not exist**: the visitor gets a not-found page that explains what the service is, not a bare error. Repeated requests for the same non-existent code must not cause repeated work in the system of record — enumeration of random codes is an expected attack.
- **Link was deleted**: same not-found page as a code that never existed.
- **Link or owning account is banned**: safety warning page with a report control, never a redirect.
- **Code collision on creation**: if a generated code is already taken, the system generates another and the creator never sees a failure. Uniqueness is enforced by the store itself, not by a check-then-write sequence, so two simultaneous creations can never receive the same code.
- **Cold cache**: the first visitor after a link falls out of cache is served correctly, just more slowly, and subsequent visitors are served from cache.
- **Cache unavailable entirely**: redirects still resolve correctly from the system of record at reduced throughput; no visitor sees an error caused solely by cache loss.
- **A link goes viral at the moment its cached entry expires**: a burst of simultaneous misses for one code must not multiply into a burst of lookups in the system of record.
- **Destination is very long or contains tracking parameters**: accepted and stored, normalised to a canonical form before storage.
- **Visitor opens the link with automated preview software** (messenger link previews): the redirect is served normally; see Assumptions for how such opens are counted in this version.

## Requirements *(mandatory)*

### Functional Requirements

#### Accounts

- **FR-001**: System MUST allow a person to register an account with an email address and a password, and to sign in and out.
- **FR-002**: System MUST scope every link and every statistic to its owning account; no creator can read or modify another creator's data.
- **FR-003**: System MUST distinguish an administrator role from a creator role, and MUST refuse administrator functions to creators.
- **FR-004**: System MUST limit each free account to 50 active links and MUST limit how many links one account can create per hour.

#### Link creation

- **FR-005**: System MUST accept a destination address and an optional creator-facing name, and MUST return a short address.
- **FR-006**: System MUST reject destinations that are malformed, that use a scheme other than http or https, that resolve to private or internal network ranges, or that point back at the service's own short-link space.
- **FR-007**: System MUST reject destinations whose domain appears on the platform's blocked-domain list.
- **FR-008**: System MUST normalise the destination address to a canonical form before storing it.
- **FR-009**: System MUST generate short codes of 7 characters drawn at random from letters and digits. Codes MUST NOT be sequential or otherwise guessable by enumeration of an ordered sequence.
- **FR-010**: System MUST guarantee code uniqueness through the storage layer's own constraint, and MUST transparently retry with a new code if one is already taken.
- **FR-011**: System MUST NOT merge links that share a destination address; each creation produces a distinct link with a distinct code, owner, and statistics.
- **FR-012**: System MUST refuse codes matching reserved words used by the service's own paths (for example `admin`, `api`, `login`, `settings`).

#### Redirect

- **FR-013**: System MUST redirect a visitor from a valid short code to its current destination address.
- **FR-014**: System MUST serve the overwhelming majority of redirects without a per-request read of the system of record.
- **FR-015**: System MUST NOT set any tracking cookie on the redirect and MUST NOT require any consent interaction from the visitor.
- **FR-016**: System MUST issue a redirect whose caching behaviour permits the destination to be changed later — a visitor's browser MUST NOT cache the short-code-to-destination mapping.
- **FR-017**: System MUST return a not-found page for unknown or deleted codes, and MUST avoid repeating work in the system of record for a code recently confirmed absent.
- **FR-018**: System MUST return a safety warning page, not a redirect, for banned links and for links of banned accounts.
- **FR-019**: System MUST keep redirects available regardless of the account's plan or its usage volume — redirect traffic is never rate-limited or blocked.

#### Statistics

- **FR-020**: System MUST count every redirect it serves and attribute the count to the correct link.
- **FR-021**: System MUST record clicks outside the visitor's request path so that recording never adds latency to the redirect.
- **FR-022**: System MUST tolerate loss of a small window of in-flight click data during a crash without losing links, accounts, or the ability to redirect.
- **FR-023**: System MUST show a creator the total click count for each of their links in the dashboard.
- **FR-024**: System MUST NOT store visitor IP addresses in plain form.

#### Editing and deletion

- **FR-025**: System MUST allow a link's owner to change its destination address and its creator-facing name.
- **FR-026**: System MUST NOT allow the short code of an existing link to be changed.
- **FR-027**: System MUST invalidate any cached copy of a link as part of the same operation that changes or deletes it, so that no visitor is served a stale destination after the change is acknowledged.
- **FR-028**: System MUST delete links by marking them deleted rather than removing the record, MUST retain their statistics, and MUST serve the not-found page for them thereafter.
- **FR-029**: System MUST hold a deleted link's code unavailable for reuse for 30 days.

#### Administration

- **FR-030**: System MUST let an administrator find any link by short code or by destination address.
- **FR-031**: System MUST let an administrator ban a single link or every link of one account, taking effect for the next visitor.
- **FR-032**: System MUST let an administrator maintain the blocked-domain list.
- **FR-033**: System MUST provide a report control on the safety warning page that places the link in the administrator's review queue.
- **FR-034**: System MUST NOT expose a creator's marketing statistics to administrators during normal operation.
- **FR-035**: System MUST expose operational health to administrators: proportion of redirects served from cache, redirect response time (typical and worst-case), redirects per second, and click-processing backlog.

### Key Entities

- **Account**: a registered creator or an administrator. Holds credentials, role, plan, creation date, banned flag, and its per-hour creation allowance.
- **Link**: one short code mapped to one destination. Holds the immutable code, the current destination, an optional creator-facing name, owner, creation date, deleted flag, banned flag, and total click count. Belongs to exactly one Account.
- **Click**: one served redirect. Holds the time and the link it belongs to. Never holds a plain visitor IP address.
- **Blocked domain**: a domain on which link creation is refused platform-wide.
- **Report**: a visitor's complaint about one link, awaiting administrator review.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A visitor who taps a short link reaches the destination without perceiving a delay — the service adds no more than 50 ms at the worst case (99th percentile) under the target load, measured from request arrival to redirect response.
- **SC-002**: At least 95% of redirects are served without touching the system of record, measured over any one-hour window in which access follows a realistic long-tail distribution — a small minority of links drawing the majority of traffic, rather than requests spread evenly across the whole corpus.
- **SC-003**: A newly registered person can produce their first working short link in under 2 minutes without instruction.
- **SC-004**: The read-optimised version sustains at least 5 000 redirects per second on the project's reference hardware, and the same load test run against the naive database-only version is recorded alongside it for comparison.
- **SC-005**: Redirect availability during the load test is at least 99.9%, with zero incorrect destinations served.
- **SC-006**: After a creator confirms a destination change, no subsequent visitor is sent to the previous destination — verified by an automated test that edits a link and immediately re-opens it.
- **SC-007**: A sustained flood of requests for non-existent codes causes no measurable increase in load on the system of record beyond the first occurrence of each code.
- **SC-008**: Total loss of the cache layer degrades throughput but produces zero redirect errors, and cache effectiveness returns to its steady-state level within 10 minutes of normal traffic.
- **SC-009**: A click count shown to a creator is no more than 30 seconds behind reality.
- **SC-010**: An administrator can locate and ban a reported link in under 1 minute from opening the queue.

## Out of Scope (this version)

Deferred deliberately, recorded so the boundary is explicit: paid plans and billing; custom codes; expiry dates; password-protected links; customer-owned domains; team accounts and roles; full analytics (geography, devices, referrers, campaign tags, unique visitors, hourly charts, CSV export); bot and preview-traffic separation; QR codes; public API for third parties; webhooks; SSO; self-hosted distribution; support-mode access to a creator's statistics with audit logging; automated abuse heuristics; business metrics dashboards.

Two of these are called out because the current version makes design choices that must not block them later: **bot separation** (counts must be able to split into human and automated without a data migration) and **hourly rollups** (raw click storage must be able to give way to compact aggregates so that a year of history is not a billion rows).

## Assumptions

- **Registration is email and password only** in this version. The description mentions Google sign-in; it is deferred, as social sign-in adds an external dependency without changing what the product proves.
- **Redirects use a temporary (non-permanent) redirect status**, because a permanently-cached redirect would make destination editing — a core promise of the product — silently fail in visitors' browsers.
- **Every open is counted as one click** in this version. Automated preview traffic from messengers is not separated out yet; the counter is understood to be inflated, and the separation is listed in Out of Scope with the constraint that it must be addable without discarding history.
- **Clicks are stored individually** in this version; hourly aggregation is deferred, and retention of raw click data is capped at 7 days so the deferral cannot become an unbounded-growth problem.
- **The service runs on a single service-owned short domain**; multi-domain support is out of scope.
- **Cache memory is bounded from day one** with least-recently-used eviction, and a cached entry's lifetime is refreshed on each hit, so that a popular link cannot expire out of cache precisely at its traffic peak.
- **The load test's reference hardware is a single machine** running the service, the database, and the cache, so that the naive-versus-optimised comparison isolates the design change rather than the infrastructure.
- **"No stale destination after an edit"** is interpreted as: the cache entry is invalidated within the same operation that writes the change, before the creator's request is acknowledged.
