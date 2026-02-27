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
  - Runs `project-self-loop-test.sh <project>` for each.
  - Prints summary counts and lists of passing/failing projects.

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

Run from inside a project directory:

```bash
cd order-service
../project-self-loop-test.sh .
```

## Notes

- If a project needs external infra (for example Kafka), place a compose file in that project directory; `project-self-loop-test.sh` will automatically `up` before test and `down` after.
