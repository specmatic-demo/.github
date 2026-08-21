# BCC Demo Workflow

Use [run-backward-compatibility-check.sh](C:\Sushant\Specmatic Job\New folder\.github\run-backward-compatibility-check.sh) as the normal entrypoint.

## Common commands

Run the full workflow with randomized changes, BCC checks, and automatic restore:

```bash
bash ./run-backward-compatibility-check.sh --mode Random
```

Run the workflow for a single project directory:

```bash
bash ./run-backward-compatibility-check.sh --mode Random --project-dir ./catalog-service
```

Run only compatible or incompatible changes:

```bash
bash ./run-backward-compatibility-check.sh --mode Compatible
bash ./run-backward-compatibility-check.sh --mode Incompatible
```

Run the full workflow and send reports after BCC succeeds:

```bash
bash ./run-backward-compatibility-check.sh --mode Random --send-reports
```

````

## Notes

`.bcc-temp/openapi-bcc` is used only for temporary backup and restore of mutated specs during a run. The final BCC outputs remain under each project's `build/reports/specmatic/backward_compatibility`.

## Lower-level scripts

These are still available for debugging or partial runs:

- [prepare-random-bcc-change.sh](C:\Sushant\Specmatic Job\New folder\.github\prepare-random-bcc-change.sh)
- [project-bcc-report.sh](C:\Sushant\Specmatic Job\New folder\.github\project-bcc-report.sh)
- [send-all-reports.sh](C:\Sushant\Specmatic Job\New folder\.github\send-all-reports.sh)
