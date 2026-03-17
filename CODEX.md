# CODEX Workspace Rules and Observations

## Purpose
This top-level folder contains multiple repositories for sample applications and a central contract repository.

## Repository Conventions
- The central contract repository is `central-contract-repository/`.
- `central-contract-repository/contracts/` can contain multiple contract types, including:
  - OpenAPI
  - AsyncAPI
  - GraphQL
  - gRPC
  - Other Specmatic-supported formats
- Prefer the term `mock` instead of `stub` in docs, comments, and communication.

## Working Notes
- Keep contracts in the central contract repository as the source of truth for sample applications.
- Keep examples aligned with their corresponding contracts.
- When editing contracts, ensure that the contract repo is pushed, before running any tests in the sample applications that depend on those contracts.
