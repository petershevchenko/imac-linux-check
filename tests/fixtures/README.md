# Test fixtures

Each subdirectory is a captured (or, where noted, hand-constructed) set of the raw command
output the collector reads, so the whole tool is testable on Linux CI without Apple hardware.

A fixture directory is consumed with `bin/imac-linux-check --fixture-dir <dir>` and contains:

| File | Stands in for |
| --- | --- |
| `system_profiler.json` | `system_profiler -json SPHardwareDataType …` |
| `hw_model.txt` | `sysctl -n hw.model` |
| `sw_vers.txt` | `sw_vers` |
| `ioreg.txt` | `ioreg -l -p IOService` |

## Provenance of these fixtures

- **`imac17-1/`** — **hand-constructed** from the directly-observed facts in the project
  spec (§11) and public `iMac17,1` specifications. It is *representative*, not a verbatim
  capture. Replace it with a real `system_profiler`/`ioreg` capture from the hardware when
  one is available; the field shapes and PCI IDs are chosen to match real output.
- **`unknown-model/`** — minimal fixture for an identifier with no dataset record.
- **`imac-t2/`** — minimal fixture exercising T2 detection (non-empty `SPiBridgeDataType`).

When a contributor sends a report for a new model, add it here as a permanent regression
fixture.
