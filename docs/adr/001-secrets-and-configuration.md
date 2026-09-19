# ADR-001: Secrets and Configuration

## Status
Accepted

## Date
2026-09-19

## Context
Because this website interfaces with external systems such as the Battle.Net API
and databases, configuration and secrets pertaining these services needs to be stored
in a secure manner conform to the Ruby on Rails best-practises.

## Decision
Configuration values that are not considered secret will be stored in their relevant
files inside the `config` folder.
Values that are considered "secret" will be stored in the `credentials.yml.enc` file.

Credentials are stored in the standard credentials file.
Even for development, we will use the live battle.net endpoint to ensure everything works.
The structure will be as follows for credentials:

```yaml
battle_net:
  client_id: ""
  client_secret: ""
```

Use `EDITOR=vi bin/rails credentials:edit` when you have the `master.key` file in place.

## Consequences
The management of secrets is controlled by version control, but requires the sharing of the
`master.key` file with developers to avoid the key being in version control.

Rails offers the `Rails.application.credentials` shorthand for accessing the values stored
inside the encrypted file. This allows us to use a uniform approach for referencing these
secrets, respect the deployment environment and not break code when we update something.

The downside is that changing secrets requires a redeployment of the application.

## Alternatives Considered
* Environment variables
* External services or dependencies


## References
* [Complete Guide to Rails Credentials and Secrets](https://wagnermatos.co.uk/articles/the-complete-guide-to-rails-credentials-and-secrets-management)
* [Official Rails Documentation](https://guides.rubyonrails.org/security.html)
