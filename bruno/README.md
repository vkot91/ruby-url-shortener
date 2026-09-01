# Snip API — Bruno collection

A manual test collection for the backend, kept in the repository so it moves
with the code. Every request in here is a request the backend answers today;

## Running it

1. Install [Bruno](https://www.usebruno.com/), then **Open Collection** and pick
   this `bruno/` directory.
2. Bring the stack up. Postgres and Redis are containers; the API is not:

   ```sh
   cd backend
   cp .env.example .env    # first time only
   docker compose up -d    # postgres + redis
   bin/rails s            # port 3001
   ```

3. Select the **Local** environment in the top-right picker.
4. Run `01 - Auth / Sign in`. That is the whole setup: it signs in as the
   seeded account and leaves an access token behind for everything else.
5. Run the folders in order — `00`, `01`, `02`, `03`. The numbering is the run
   order, not a category.

## The account

`dev@snip.test` / `development password`, held in the Local environment as
`email` and `password`. It is one row in `backend/spec/fixtures/accounts.yml`,
loaded automatically when the database is created and re-loadable at any time:

```sh
cd backend && bin/rails db:fixtures:load
```

That command is not additive — it empties every table the fixtures cover and
refills it. Which is the point: the collection runs against the same seven links
and four accounts on every machine. Alongside `dev` there is an `admin` account
for the `/admin/*` requests, a `rival` account that owns links `dev` must never
see, and a `suspended` one whose links serve the warning page.

The credentials are committed deliberately. They are a development fixture, not
a secret, and their value is being identical on every machine and after every
`db:reset` — a collection you have to register an account for before you can use
it is a collection nobody runs. The seed refuses to create the account in
production.

`01 - Auth / Register` does *not* use this account. It generates a throwaway
address on each run, because its job is to test registration and because a fixed
address would collide with the unique index on the second pass.

The whole collection is runnable in one pass with Bruno's collection runner, or
from the CLI:

```sh
npx @usebruno/cli run --env Local
```

## Variables

`environments/Local.bru` holds the values that do not change between runs: where
the stack is (`baseUrl`, `shortDomain`, `appUrl`, matching the defaults in
`backend/.env.example`) and the seeded credentials (`email`,
`password`).

Everything else is a **runtime variable**, set by a request's post-response
script and never written to disk:

| Variable | Set by | Used by |
| --- | --- | --- |
| `accessToken` | Register, Sign in, Refresh | collection-level bearer auth |
| `refreshToken` | Register, Sign in, Refresh | Refresh, Sign out |
| `spentRefreshToken` | `Refresh` (pre-request) | `Refresh - replay a spent token` |
| `newAccountEmail`, `newAccountPassword` | `01 - Auth / Register` | `Register - duplicate email` |
| `failedSignInEmail` | `Sign in - wrong password` (pre-request) | itself |
| `linkId`, `linkCode` | `02 - Links / Create link` | `03 - Redirect` |

Runtime variables were chosen over environment variables on purpose: an
environment variable set from a script is written back into
`environments/Local.bru`, which would put a live credential under version
control and produce a diff on every run. Runtime variables live for the session
only. The cost is that they are gone after an app restart — re-run `Register`,
or `Sign in` if you still have an account.

Authentication is declared once, on the collection: bearer, `{{accessToken}}`.
Requests that must go out unauthenticated say `auth: none` for themselves, and
that is the assertion, not an oversight — see
`02 - Links / Reject - unauthenticated`.

## Redirect requests

Bruno follows redirects by default, which would send `03 - Redirect / Follow a
short code` on to `example.com` and hide the status, the `Location`, and the
`Cache-Control` header — which is everything that request exists to check. Each
request in that folder carries `followRedirects: false` in its settings. If your
Bruno version predates that setting, turn **Follow redirects** off in the
request's Settings tab.

## Rate limits you will meet

All windows are one hour (`RateLimiting::WINDOW`), counted in Redis under the
`ratelimit` namespace.

| Endpoint                     | Limit      | Keyed by      |
| ---------------------------- | ---------- | ------------- |
| `POST /api/v1/registrations` | 10         | origin        |
| `POST /api/v1/sessions`      | 10         | origin        |
| `POST /api/v1/sessions`      | 5          | email address |
| `POST /api/v1/auth/refresh`  | 60         | origin        |
| `POST /api/v1/links`         | 30         | account       |
| `GET /:code`                 | none, ever | —             |

That last row is a requirement, not an omission (FR-019, Principle I): redirect
traffic is never throttled, whatever the owning account does on the API.

If you hit a limit while iterating, `cd backend && docker compose restart redis` clears the
counters.
