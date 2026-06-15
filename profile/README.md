# Specmatic Demo Org

This repository demonstrates a multi-service organization with:
- Multiple app/service repositories (`web-bff`, `order-service`, etc.)
- A shared central contracts repository (`central-contract-repository`)
- Loop-test scripts to validate each service contract in isolation

## Architecture

High-level service architecture, dependencies, and protocol/spec details are documented in:
- `service-architecture.md`

The central contract files are under:
- `central-contract-repository/contracts`

## Prerequisites

- Java (for `specmatic-enterprise`)
- `specmatic-enterprise` command available in `PATH`, or alias configured as:
  - `specmatic-enterprise='java $JAVA_OPTS -jar ~/.specmatic/specmatic-enterprise.jar'`
- Docker + Docker Compose (for projects that need infrastructure, e.g. Kafka)

## Shell Scripts

- `loop-test.sh`
  - Runs from the contracts directory (or root if contracts are under `.`).
  - Iterates through spec files and runs `specmatic-enterprise mock SPEC_FILE` and `specmatic-enterprise test SPEC_FILE`.
  - Prefixes output by source (`[mock]`, `[test]`) and prints pass/fail summary.

- `project-self-loop-test.sh`
  - Runs self loop test for one project:
  - Starts optional Docker Compose infra (if compose file exists in the project).
  - Starts `specmatic-enterprise mock` from `<project>/loop-test`.
  - Runs `specmatic-enterprise test` from `<project>`.
  - Cleans up mock and compose resources on exit/interruption.

- `all-self-loop-test.sh`
  - Discovers all direct subprojects with `.git`, `specmatic.yaml`.
  - Runs `central-contract-repository/ci.sh` first.
  - Runs federated provider `ci_central_repo_report.sh` scripts before service test runs.
  - Runs `project-self-loop-test.sh <project>` for each.
  - Prints summary counts and lists of passing/failing projects.

- `send-all-reports.sh`
  - Sends `central-contract-repository` first.
  - Sends federated provider central repo reports next.
  - Waits before sending service reports so central repo baselines can be processed.
  - Sends the remaining service reports from repo root.

- `specmatic-loop-common.sh`
  - Shared helpers used by the scripts (colors, command resolution, output prefixing, process-tree cleanup).

## Sample Usage

Run loop tests for all specs from root:

```bash
./loop-test.sh
```

Run self loop test for one project:

```bash
./project-self-loop-test.sh notification-service
```

Run self loop tests for all projects:

```bash
./all-self-loop-test.sh
```

Run generated reports send phase:

```bash
./send-all-reports.sh
```

Run from inside a project directory:

```bash
cd order-service
../project-self-loop-test.sh .
```

## Notes

- If a project needs external infra (for example Kafka), place a compose file in that project directory; `project-self-loop-test.sh` will automatically `up` before test and `down` after.

## Run Locally

To mirror the GitHub Actions layout locally, run from this repository root after submodules are populated:

```bash
git submodule sync --recursive
git submodule update --init --recursive
```

The recommended local flow is two-phase:

1. Generate reports with Insights down:

```bash
unset SEND_REPORT
./all-self-loop-test.sh
```

2. Start Insights, then send the generated reports:

```bash
./send-all-reports.sh
```

Notes:
- `all-self-loop-test.sh` is the production orchestration path used by the workflow.
- When `SEND_REPORT` is set, `all-self-loop-test.sh` waits 120 seconds after federated central repo report sends before running service builds. This avoids a race where service builds are processed before their central repo baselines.
- `send-all-reports.sh` is a local/manual helper. Production does not call it directly.
