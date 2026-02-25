---
name: specmatic
description: "Use for Specmatic work in this multi-repo demo org: editing contracts in central-contract-repository, updating service specmatic.yaml files, running self-loop tests, configuring dependency mocks, and debugging contract mismatches across OpenAPI, AsyncAPI, GraphQL, and protobuf specs."
---

# Specmatic

Execute Specmatic tasks using the repository conventions and scripts in this workspace.

## Workspace Context

- Treat `central-contract-repository/contracts/` as the source of truth for contracts.
- Keep service repos (`web-bff`, `order-service`, etc.) aligned with central contracts through their `specmatic.yaml` references.
- Prefer the term `mock` instead of `stub`.
- Push contract changes in `central-contract-repository` before validating dependent services.

## Supported Contract Shapes In This Repo

- HTTP: OpenAPI (`.../http/openapi.yaml`)
- Events: AsyncAPI (`.../events/asyncapi.yaml`)
- Graph: GraphQL schema (`.../graphql/schema.graphql`)
- RPC: protobuf (`.../rpc/*.proto`)

## Interaction Rules

- Synchronous API SUT alignment (OpenAPI, GraphQL, protobuf/gRPC): Every synchronous API interaction implemented by an application must align with the spec referenced under `systemUnderTest` in that application's `specmatic.yaml`.
- Synchronous API dependency declaration (OpenAPI, GraphQL, protobuf/gRPC): If an application calls another application's synchronous API, declare the called application's corresponding contract under `dependencies.services` in the caller's `specmatic.yaml`.
- AsyncAPI SUT receive alignment: For an AsyncAPI system under test, every topic the application subscribes to must align with channels/operations modeled as `action: receive` in the SUT spec.
- AsyncAPI SUT send alignment: For an AsyncAPI system under test, every topic the application publishes/sends to must align with channels/operations modeled as `action: send` in the SUT spec.
- AsyncAPI inverse interaction handling: If observed runtime interaction direction is inverse to the SUT AsyncAPI action, model that interaction as a dependency rather than SUT behavior, and declare the relevant AsyncAPI contract under `dependencies.services`.
- Health endpoint exception: Ignore `/health` endpoints for contract matching and violation checks across all spec types.

## Primary Workflow

1. Locate the target service contract references in `<service>/specmatic.yaml`.
2. Apply contract edits in `central-contract-repository/contracts/...` first.
3. Update dependency wiring in `<service>/specmatic.yaml`:
- Add or remove `dependencies.services` entries.
- Add matching `components.services` definitions and spec paths.
- Add matching `components.runOptions` blocks for mocks/tests.
4. Run service loop tests from repo root:
- Single service: `./project-self-loop-test.sh <service-dir>`
- All services: `./all-self-loop-test.sh`
5. Commit and push nested repos first, then commit parent repo submodule-pointer updates.

## Commands

- Single service self-loop:
```bash
./project-self-loop-test.sh notification-service
```

- Run from within a service:
```bash
cd order-service
../project-self-loop-test.sh .
```

- All services:
```bash
./all-self-loop-test.sh
```

- Enable generative tests behavior for dependency mocks:
```bash
SPECMATIC_GENERATIVE_TESTS=true ./project-self-loop-test.sh web-bff
```

## Runtime Expectations

- `project-self-loop-test.sh` requires:
- `yq` for parsing `specmatic.yaml`
- `specmatic-enterprise` in `PATH`, or `~/.specmatic/specmatic-enterprise.jar`
- Docker Compose only when a service has a compose file
- The script clears local `build/` and `.specmatic/` before execution.

## Failure Triage

- `specmatic.yaml not found`:
- Run from repo root and pass a valid service directory.

- `No dependencies.services ... skipping mock startup`:
- Expected when a service has no dependency mocks configured.

- AsyncAPI/MQTT test failures:
- Verify broker host/port in `runOptions.asyncapi.servers`.
- If infra is required, ensure service-level compose file exists and starts.

- Contract path errors:
- Verify `path` entries in `specmatic.yaml` match files under `central-contract-repository/contracts/`.

- Command resolution errors:
- Ensure Java is available and `specmatic-enterprise` command or jar fallback is configured.
