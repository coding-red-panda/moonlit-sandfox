# CLAUDE.md — moonlit-sandfox

## Stack

- **Rails** 8.1.3 on **Ruby 4.0.6** (rvm; see `.ruby-version`)
- **PostgreSQL 18** in Docker (see Database below) — no local Postgres install
- **Frontend**: Propshaft + ImportMap + Hotwire (Turbo & Stimulus). No Node build step, no React.
- **Background jobs / cache / cable**: Solid Queue, Solid Cache, Solid Cable — all backed by Postgres. **Not Sidekiq, no Redis.**
- **Testing**: RSpec (`rspec-rails`) + factory_bot + shoulda-matchers + webmock
- **`json` is pinned to `< 3`.** json 3.x takes parser options as keywords, but
  `ActiveSupport::JSON.decode` still passes them positionally, which breaks *all* cookie
  and session deserialization on Rails 8.1 (`ArgumentError: wrong number of arguments
  (given 2, expected 1)`). This is rails/rails#58685 — closed as fixed by rails/rails#58601
  (`::JSON.parse(json, **options)`), backported to `8-1-stable`, but **not in any released
  Rails 8.1.x as of 8.1.3.1**. The pin lifts via a Rails bump, not a json bump. Close
  Dependabot json PRs until then, and re-test sessions when unpinning.
- **Deploy**: not yet decided. A production `Dockerfile` exists; Kamal was deliberately removed.
- **Dev environment**: WSL2 (Debian) on Windows, with Docker Desktop's WSL integration

## Commands

Use the binstubs in `bin/` — they are what CI runs.

```bash
bin/setup              # install gems, start Docker, prepare databases, then run the server
bin/setup --skip-server
bin/dev                # start the server (plain `rails server`; there is no Procfile/foreman)

bin/rspec                              # all specs
bin/rspec spec/models/post_spec.rb     # one file
bin/rspec spec/models/post_spec.rb:42  # one example

bin/rubocop            # lint
bin/rubocop -A         # autocorrect, including unsafe corrections

bin/rails db:migrate
bin/rails db:rollback
bin/rails console
bin/rails dbconsole    # psql into the dev database
```

## Database

Postgres runs in a container defined by `compose.yaml`:

```bash
docker compose up -d --wait   # start (bin/setup does this too)
docker compose stop           # stop, keep data
docker compose down -v        # destroy, including all data
docker compose logs -f postgres
```

- Container name `moonlit-sandfox-db`, image `postgres:18-alpine`, host port **5432**.
- **Port 5432 is shared with the `retrobunny-db` container from another project.** Only one can run at a time.
- `config/database.yml` reads `DB_HOST` / `DB_PORT` / `DB_USERNAME` / `DB_PASSWORD`, defaulting to `localhost:5432` and `moonlit_sandfox` / `moonlit_sandfox`. No env vars are needed for normal local work.
- The dev password is committed deliberately: it is a throwaway local container. Production reads `MOONLIT_SANDFOX_DATABASE_PASSWORD` from the environment.
- Postgres 18+ requires the volume mounted at `/var/lib/postgresql`, **not** `/var/lib/postgresql/data`. Mounting the old path makes the container crash-loop.

## Style and linting

RuboCop uses the **official gem with stock defaults** (`rubocop` plus the `rails`, `performance`, `rake`, `rspec` and `rspec_rails` plugins). `rubocop-rails-omakase` was deliberately removed.

- **Stock defaults mean single-quoted strings**, which is the opposite of what Rails generators emit.
- **Always run `bin/rubocop -A` after any `rails generate`**, or the generated file will fail lint.
- Only two cops are disabled: `Style/FrozenStringLiteralComment` and `Style/Documentation`.
- The repo is at zero offences. Keep it there.

## Testing

- Specs live in `spec/`. `spec/support/**/*.rb` is auto-required by `rails_helper`.
- **Tag spec type explicitly** — `RSpec.describe Post, type: :model`. `infer_spec_type_from_file_location!` is intentionally left off because rspec-rails has marked it legacy. The generators emit the tag for you; hand-written specs need it. shoulda-matchers' ActiveRecord matchers only load into tagged groups.
- factory_bot syntax methods are included, so use `create(:post)`, not `FactoryBot.create(:post)`.
- Factories go in `spec/factories/`; `rails generate model` creates one automatically.
- The test database must be running — the Docker container serves both dev and test.

## CI

`.github/workflows/ci.yml` runs on pull requests and pushes to **`master`** (this repo has no `main` branch):

| Job | Runs |
|---|---|
| `scan_ruby` | `bin/brakeman`, `bin/bundler-audit` |
| `scan_js` | `bin/importmap audit` |
| `lint` | `bin/rubocop -f github` |
| `test` | `bin/rails db:prepare`, then `bin/rspec`, against a `postgres:18-alpine` service |

The test job uses `db:prepare`, not `db:test:prepare` — the latter exits non-zero when `db/schema.rb` does not exist yet.

## Authentication

Battle.net OAuth2, hand-rolled in `AuthenticationController` — **no OmniAuth**. See
`docs/adr/002-authentication.md` for the full decision; `omniauth-bnet` is deliberately
rejected (unmaintained since 2018, pins the vulnerable OmniAuth 1.x line).

- Endpoints live on `oauth.battle.net`; data APIs on `eu.api.blizzard.com`. Different hosts.
- Non-secret config in `config/battle_net.yml`; `client_id`/`client_secret` in credentials.
- Access tokens are **never persisted** — Battle.net issues no usable refresh token, so the
  callback spends the token in-request and discards it.
- `accounts.battle_net_id` is the `sub` claim, not the battletag (battletags are mutable).
- The session holds nothing but `account_id`. `current_account` / `signed_in?` /
  `require_authentication` live in `ApplicationController`.
- PKCE is unavailable on Battle.net, so `state` is the only forgery defence. Do not drop it.
- **Browse to `http://localhost:3000`, not the `http://127.0.0.1:3000` that `bin/dev` prints.**
  Session cookies are per-host, so starting the flow on one and returning on the other loses
  the state and fails the login. `create` redirects to the canonical host to prevent this;
  request specs must `host! 'localhost'`.

Only the identity half is built. Guild membership, character ranks and permissions are
phase two and still need decisions — see the ADR.

## Not yet decided

Do not assume these exist; ask before building on them.

- **Authorization** — no Pundit or CanCan. Guild-rank permissions are not built.
- **Domain models** — `app/models` has `Account` and `BattleNet::Client` only.
- **Soft deletes, admin UI, API layer** — none.

## Conventions

- Follow default Rails structure. Do not add `app/services`, `app/components` or similar without asking; prefer models, concerns and `app/views/shared`.
- Prefer Hotwire over custom JavaScript.
- Keep the project inside the WSL filesystem (`~/src/...`). Running it from `/mnt/c` is dramatically slower.
