# ADR-003: Session and Character Management

## Status
Accepted

## Date
2026-10-03

## Context
Because the Blizzard API does not offer refresh tokens, and requires re-approval of the user
when fetching their account information, we're going to limit the session on the website to
just 12 hours. The Blizzard API token is valid for 24h, but this allows us to offer a live session
when user visits the website, and re-affirm the permissions on every login.

## Decision

Every time the user logs in, and we obtain a new account token, the following steps will be performed:

* Authentication with the Blizzard API.
* On successful Authentication, the session is started for 12 hours, persisting the behavior we have.
  * Storing the battle_net id for the current user
  * Create a DB record to represent the account using the `Account` model
* A background job is scheduled to fetch the account's characters.

### Character Data

A battle_net ID can have multiple WoW accounts. If the API supports the behavior, all active World of Warcraft
accounts should be loaded and their characters retrieved. The profile payload confirms it does: a single
Battle.net account came back with two game accounts holding twelve and four characters. For this we will need
to introduce the following:

1. A new entity called `WorldOfWarcraft::Account` that tracks the actual World of Warcraft game accounts.
2. An `Account` can have one or more `WorldOfWarcraft::Account` relations.
3. A new entity called `WorldOfWarcraft::Character`, linked to a `WorldOfWarcraft::Account`.
4. For the `WorldOfWarcraft::Character`, we store the following information:
   1. Unique Database ID
   2. ID provided by the API for easy referencing (if available)
   3. Name
   4. Realm slug — characters are only unique per realm, and the roster is realm-scoped
   5. Class
   6. Level
   7. Guild Rank
5. Guild Ranks are usually fixed, but we should create a `WorldOfWarcraft::GuildRank` entity and use that as
   relation on the character. This allows us to add custom functionality later.
6. `ActiveJob` to run tasks in the background.
7. A new `FetchCharactersJob` which takes the account and pulls + parses the characters:
   1. New ones are added
   2. Old ones are deleted
   3. Levels / Rank are verified on each pull and updated as needed.

### The rank ladder

Blizzard's roster endpoint returns ranks as bare integers and nothing else — no names, and no notion of who is
an officer. Both are therefore ours to keep, which is the strongest argument for the `GuildRank` entity. The
ladder is seeded by `bin/rails db:seed`:

| Rank | Name | Officer |
|---|---|---|
| 0 | Caravan Leader | yes |
| 1 | Council | yes |
| 2 | Desert Fang | no |
| 3 | Scroll Sage | no |
| 4 | Scavenger | no |
| 5 | Pathfinder | no |
| 6 | New Tail | no |
| 7 | Caravan Friend | no |
| 8 | Friend/OOC Alt | no |
| 9 | Neighbour | no |

`officer` is a boolean on the entity rather than a derived rule, so promoting a rank is a data change and not a
deploy. It is stored only; nothing reads it for permissions yet — that is authorization, and it stays blocked on
the admin panel ADR.

### Solid Queue, not Sidekiq

`ActiveJob` runs on **Solid Queue**, not Sidekiq. Solid Queue is already configured end to end — `config/queue.yml`,
`config/recurring.yml`, the Puma plugin, and a dedicated `queue` database in production — and it is Postgres-backed,
so it needs no Redis container, no CI service and no addition to a deploy story that does not exist yet. Sidekiq
would have brought all three. Active Job keeps the decision reversible if the queue ever outgrows Postgres.

Development keeps Rails' default `:async` adapter. Running Solid Queue there would mean a second development
database purely to watch jobs run, and the test adapter already round-trips job arguments through serialization,
which is the part worth exercising.

### Carrying the access token into the job

`/profile/user/wow` is account data: it needs the signed-in user's own token, and a `client_credentials` token
will not reach it. The job therefore has to carry that token past the end of the request it was issued in, which
ADR-002 ruled out.

The token travels **sealed in an encrypted envelope** (`BattleNet::AccessToken#sealed`), encrypted under a key
salted off `secret_key_base` and stamped with the same 24-hour expiry Battle.net gives the token itself. What
lands in the Solid Queue tables is ciphertext, worthless on its own, and it times itself out even if the job row
outlives the job. `FetchCharactersJob` sets `log_arguments = false` so the ciphertext does not reach the log
either. A token that cannot be unsealed is not retried: the user has to log in again, and the characters are
refreshed then.

The guild roster needs none of this. It is game data, reachable with a `client_credentials` token, so it is split
into a second job — `SynchronizeGuildRanksJob` — that holds no user credential at all and can be re-run at any
time. This also resolves an ordering problem in the list above: the job cannot "take the account and wow account",
because the WoW accounts are not known until the profile call inside it returns.

### Session mechanics

`expire_after: 12.hours` on the cookie store only asks the browser to drop the cookie; a client is free to keep
sending an expired one. The deadline is therefore also written into the session payload as `expires_at` and
re-checked server-side on every request, with `reset_session` on the way out.

## Alternatives Considered
- None

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
