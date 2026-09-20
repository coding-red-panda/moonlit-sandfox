# ADR-002: Authentication

## Status
Accepted

## Date
2026-09-19, amended 2026-09-20 (guild data: sessions, settings and payload recording)

## Context
Content on the website is sometimes restricted to members of the guild.
To achieve this, we require an authentication system that allows people to sign up,
and login using credentials. We need to support a system that is accessible by everyone
and supported on every platform.

## Decision
Authentication will be handled by the Battle.Net OAuth2 implementation.
This allows us to tie our entire authentication and logic on whether someone can interact
with the internal parts of the website based on the position they have inside the guild.

The Battle.Net API allows us to access the account information and characters.
This gives us the opportunity to automatically perform the following on sign-up:

* Verify this person plays World of Warcraft
* Verify this person is a member of our guild
* Assign permissions based on the highest role any of their characters have.
* Lock/Unlock features based on the assigned permissions.

### Account Profile
Authenticating and accepting the usage of the battle.net API will result on a succesfull profile
being created on our side. Using the described Authorization Flow, on sign-up we ask for the permission
to pull profile and World of Warcraft account data. We will ask the following scopes:

* `wow.profile`: To pull World of Warcraft data such as guild membership and characters
* `openid`: To access the general user-info profile for setting up the account on our side.

Scopes are sent as a single space-separated string: `openid wow.profile`.

### Implementation: hand-rolled, not OmniAuth
We implement the authorization code flow directly in an `AuthenticationController`
rather than adopting a gem.

The `omniauth-bnet` gem listed under References is **not** suitable: its last release
(2.0.0) dates from October 2018 and it pins `omniauth ~> 1.0`. OmniAuth 1.x is the line
affected by the request-phase CSRF issue (CVE-2015-9284), fixed only in OmniAuth 2.x,
which that gem cannot accept. It is kept in the References purely as prior art.

The flow is two endpoints and roughly forty lines of code, so the dependency buys us
nothing in exchange for the risk.

### Endpoints
The OAuth endpoints are region-independent and live on `oauth.battle.net`. This is a
different host from the data APIs, which are region-specific and are always `eu.api.blizzard.com`
for this project.

Taken from `https://oauth.battle.net/.well-known/openid-configuration`:

| Purpose | Endpoint |
|---|---|
| Authorization | `https://oauth.battle.net/authorize` |
| Token | `https://oauth.battle.net/token` |
| Userinfo | `https://oauth.battle.net/userinfo` |
| End session | `https://oauth.battle.net/logout` |
| Revocation | `https://oauth.battle.net/revoke` |

The client credentials are sent to the token endpoint using HTTP Basic authentication,
not as body parameters.

### Redirect URI
Blizzard matches the redirect URI exactly, including scheme, port and path. Every
environment therefore needs its own entry registered on the developer portal.
Registering the bare origin (`http://localhost`) is not sufficient.

Non-secret per-environment configuration, including the redirect URI, lives in
`config/battle_net.yml` per ADR-001.

The browser must already be on the redirect URI's host when the flow starts. Session
cookies are scoped by hostname, and `127.0.0.1` and `localhost` are distinct hosts even
though they resolve to the same machine. Starting the flow on one and returning to the
other means the callback arrives with no session cookie, so the `state` lookup finds
nothing and the login is rejected — a failure that looks like tampering rather than a
configuration mistake. `bin/dev` prints the `127.0.0.1` form, so this is easy to trip over.

`AuthenticationController#create` therefore bounces the user to the canonical host before
issuing any state.

### Request forgery protection
The discovery document advertises no `code_challenge_methods_supported`, so **PKCE is not
available** on Battle.net. The `state` parameter is consequently our only defence against
a forged callback, and is mandatory:

1. `/login` generates a random `state` and stores it in the session.
2. `/callback` compares the returned `state` against the stored one and deletes it.
3. A missing or mismatched `state` aborts the login.

### Tokens are not persisted
Battle.net does not issue usable refresh tokens for the authorization code flow; Blizzard
staff have confirmed that a token "can't properly [be refreshed] without user interaction".
The discovery document does advertise a `refresh_token` grant server-wide, but that is not
the same as our client being issued one, and we do not rely on it.

We therefore do not store access tokens at all. The callback uses the token once, in
request, to fetch the userinfo claims, and then discards it. Any World of Warcraft profile
data we need must be fetched during that same callback while the token is live.

This avoids storing a credential we could not refresh, and means Active Record Encryption
is not required for this feature.

### Fetching profile data: BattleNet::Session
Because the token is spent in-request, everything that needs World of Warcraft data has
to run inside the callback. `BattleNet::Client#authenticate` exchanges the authorization
code and returns a `BattleNet::Session`: a small object holding the live token, bound to
the client that issued it.

The token is never exposed as an attribute and is redacted from `#inspect`, so it cannot
reach a log line or an exception report. The session is garbage at the end of the
request, and nothing stores it.

Unlike the OAuth endpoints, the data endpoints it wraps are region-specific and require
`namespace=profile-eu` and a locale on every call:

| Purpose | Endpoint |
|---|---|
| Account profile | `GET https://eu.api.blizzard.com/profile/user/wow` |
| Guild | `GET https://eu.api.blizzard.com/data/wow/guild/{realmSlug}/{nameSlug}` |
| Guild roster | `GET https://eu.api.blizzard.com/data/wow/guild/{realmSlug}/{nameSlug}/roster` |

Only the account profile genuinely needs the user's token. The guild and roster endpoints
are public game data and answer a `client_credentials` token just as happily — verified
while seeding the settings above. We still fetch the roster with the user's session because
it is free to do so while we are already holding one, but rank evaluation is not constrained
by the token's lifetime here: the roster can be refreshed on a schedule for every member at
once, rather than only when someone happens to log in.

### Configuration: the settings table
The guild we match members against is an operational value, not a constant. It is not a
secret, so credentials are the wrong home; it changes independently of the code, so
`config/battle_net.yml` is the wrong home too — a realm transfer or a guild rename should
not need a deploy.

A single `settings` table holds values like this: a unique string `key` and a string
`value`, read and written through `Setting[]`, `Setting[]=` and `Setting.fetch`. Two keys
matter today:

| Key | Meaning |
|---|---|
| `guild.realm_slug` | the realm the guild lives on, e.g. `silvermoon` |
| `guild.name_slug` | the guild's slug as it appears in the roster URL |

Values are strings by design. Anything with structure, validations or relationships has
outgrown this table and deserves a model of its own.

Both are seeded in `db/seeds.rb` with the guild this site is for, confirmed against the
API and the armory rather than guessed:

| Key | Value |
|---|---|
| `guild.realm_slug` | `argent-dawn` (Argent Dawn EU, realm id 536) |
| `guild.name_slug` | `moonlit-sandfox` (Moonlit Sandfox, guild id 90944968, Horde) |

The slug rules are not obvious and are worth recording: the guild name is lowercased with
spaces replaced by hyphens. `moonlit%20sandfox` and `moonlitsandfox` both return 404.

The seed uses `find_or_create_by!`, not `Setting#[]=`. These are values meant to be changed
at runtime, so re-running the seeds must not stamp on a realm transfer or a rename that has
already been applied. If they are ever cleared the roster call is skipped with a logged
warning and the login still succeeds.

### Guild synchronization
Pulling the profile is not the controller's work. `Services::GuildSynchronization` takes
the account and the session and does it, leaving `AuthenticationController#callback` at
three lines.

It lives in `app/models/services/` rather than a new `app/services/` top-level directory,
so the default Rails structure is preserved: it is a plain object under an existing
autoload root, in the same way `BattleNet::Client` is.

It never raises. A Battle.net outage, a 503 from the profile API or an unconfigured guild
costs the user nothing — identity is already established, and the data is pulled again on
the next login regardless. Failures are logged and the sign-in continues.

### Recording payloads instead of modelling them
We do not yet know the shape of the profile and roster responses well enough to design
tables for them, and the authorization decisions handed off below depend on that shape.
Rather than
guess, `GuildSynchronization` writes each response verbatim to `log/payloads` through
`Services::PayloadRecorder` and stores nothing in the database.

Those files contain real battletags, character names and guild membership, so
`log/payloads/` is in `.gitignore`. This is reconnaissance, not a cache: nothing ever
reads it back, and the directory — along with the recorder — should be removed once a real
schema for this data is settled.

### Identity
The stable identifier for an account is the `sub` claim from the userinfo response, which
is the Battle.net account ID. It is stored as `accounts.battle_net_id` with a unique index.

The battletag is **not** an identifier. Users can change it, so keying on it would orphan
accounts on rename. It is stored as a display attribute and refreshed on every login.

### Sessions
A successful callback resets the session and writes only the account's primary key into it.
The presence of that key means the request is authenticated; its absence means logged out.
No other identity data is kept in the session.

This relies on the session cookie being secure, so `config.force_ssl` is enabled in
production. Logging out is a session reset on our side only — it does not end the user's
Battle.net SSO session, which Blizzard keeps for 30 days. A user clicking "log in" again
will usually be returned without being prompted.

### Phased delivery
Both phases are built, and this ADR is complete:

* **Phase 1 (built)** — `/login`, `/callback`, `/logout`, an `Account` record carrying the
  Battle.net ID and battletag, and a session.
* **Phase 2 (built)** — the data access the verification bullets need: `BattleNet::Session`,
  the `settings` table naming the guild, and `Services::GuildSynchronization` fetching the
  account profile and the guild roster on every login and recording them to
  `log/payloads`. It reads Battle.net but writes nothing to the database.

### What this ADR does not decide
The four verification bullets in the Decision above describe what authenticating *enables*.
Acting on them — deriving a rank and granting permissions from it — is authorization, and
it is **handed off to its own ADR rather than deferred within this one**. This ADR ends at
the point where the guild data is in hand.

The handoff is ordered: an admin panel is needed before authorization can be set up, so the
admin panel gets an ADR first and the authorization ADR follows it. Neither exists yet, and
no authorization library has been chosen.

Three findings from building phase 2 are inputs to that authorization ADR, recorded here so
they are not rediscovered:

* **"Highest role" still needs defining.** Guild ranks are per-character integers where 0
  is the Guild Master, so an account's effective rank is the *lowest* numeric rank across
  its characters in the guild.
* **Ranks are not contiguous.** The live roster of 135 members uses ranks 0, 1, 2 and 5
  through 9; ranks 3 and 4 are unused. A rank-to-permission mapping cannot assume a range.
* **The roster needs no user token** (see Fetching profile data), so rank evaluation is not
  forced to happen during a login.

## Consequences
Adopting the OAuth2 implementation and the Battle.Net API means we are tied to the implementation
and uptime of Blizzard's API. While this can pose a risk in the website not being accessible,
the downside makes up for the positive points this brings as described in the `Decision`.

This also requires us to maintain an official application on the developer site.
And people need to agree with us pulling some account information.

Pulling profile and character data will always be done from the EU API endpoints.
We are a European based guild and play on the EU servers.

Because tokens are not persisted, a member's *own* character list can only be re-read when
they log in again. The guild roster is not subject to this — it needs no user token — so a
stale rank is a choice the authorization ADR can revisit rather than a constraint
Battle.net imposes on us.

Logging in now costs two extra Battle.net calls, so a slow or unavailable data API makes
the callback slower. Both are treated as non-fatal, so the worst case is a sign-in that
completes with no guild data rather than one that fails.

`log/payloads` accumulates one file per API call per login and is never pruned. It is
acceptable only because it is temporary and development-only; it must be deleted, and the
recorder removed, before this reaches production with real users.

## Alternatives Considered
* Manual Authentication
  * Requires secure coding
  * Fragile
  * A lot of work to support all possible authentication systems
* Social Media Authentication
  * Too specific per platform
  * Not everyone uses it
* No Authentication
  * Unacceptable, we need some hidden parts on the website.
* OmniAuth via `omniauth-bnet`
  * Unmaintained since 2018 and pinned to a vulnerable OmniAuth major version.

## References

* [Battle.NET OAuth Guide](https://community.developer.battle.net/documentation/guides/using-oauth)
* [OIDC Endpoints](https://community.developer.battle.net/documentation/guides/using-oauth/oidc-endpoints)
* [OIDC Discovery Document](https://oauth.battle.net/.well-known/openid-configuration)
* [Omniauth-bnet](https://rubygems.org/gems/omniauth-bnet) — prior art only, see Decision
* [Omniauth-bnet GitHub](https://github.com/Blizzard/omniauth-bnet)
* [EU API Endpoint](https://eu.api.blizzard.com)
* [Namespace Documentation](https://community.developer.battle.net/documentation/world-of-warcraft/guides/namespaces)
* [Account Profile API](https://develop.battle.net/documentation/world-of-warcraft/profile-apis)
* [Guild Roster API](https://develop.battle.net/documentation/world-of-warcraft/game-data-apis)
* [Usage Guide](https://community.developer.battle.net/documentation/guides/getting-started)
* [Authorization Flow](https://community.developer.battle.net/documentation/guides/using-oauth/authorization-code-flow)
* [Blizzard staff on refresh tokens](https://us.forums.blizzard.com/en/blizzard/t/oauth-api-refresh-token/559/2)
