# ADR-002: Authentication

## Status
Accepted

## Date
2026-09-19

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
Only the identity half of this ADR is built initially:

* **Phase 1 (built)** — `/login`, `/callback`, `/logout`, an `Account` record carrying the
  Battle.net ID and battletag, and a session.
* **Phase 2 (not built)** — the four verification bullets above. Each needs additional
  calls to the World of Warcraft Profile API and the guild roster, which is a separate
  protected resource. "Highest role" needs defining before it can be implemented: guild
  ranks are per-character integers where 0 is the Guild Master, so the account's effective
  rank is the *lowest* numeric rank across its characters in our guild. The guild and realm
  we match against are also still undecided.

Authorization itself (who may see what, once ranks are known) is out of scope for this ADR
and has no library chosen.

## Consequences
Adopting the OAuth2 implementation and the Battle.Net API means we are tied to the implementation
and uptime of Blizzard's API. While this can pose a risk in the website not being accessible,
the downside makes up for the positive points this brings as described in the `Decision`.

This also requires us to maintain an official application on the developer site.
And people need to agree with us pulling some account information.

Pulling profile and character data will always be done from the EU API endpoints.
We are a European based guild and play on the EU servers.

Because tokens are not persisted, guild membership and rank can only be re-evaluated when
the user logs in again. Any cached rank is therefore as stale as the user's last login.

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
* [Usage Guide](https://community.developer.battle.net/documentation/guides/getting-started)
* [Authorization Flow](https://community.developer.battle.net/documentation/guides/using-oauth/authorization-code-flow)
* [Blizzard staff on refresh tokens](https://us.forums.blizzard.com/en/blizzard/t/oauth-api-refresh-token/559/2)
