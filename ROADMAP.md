# Roadmap

The build order deliberately starts narrow: a tool that is confidently right about a few
models is more useful, and more trustworthy, than one that is vaguely right about twenty.

## Milestones

1. **Schema + validation pipeline + one verified model.** ✅ *Done.*
   JSON Schema for model/component records, deterministic `index.json` generator,
   data-integrity tests, `validate.yml` CI, MIT/CC0 licensing, verified `iMac17,1`.

2. **Collector skeleton + fixture harness.** 🚧 *In progress.*
   `bin/imac-linux-check` (zsh, no third-party deps) with the `--fixture-dir` I/O boundary
   so the whole tool is testable on Linux CI without Apple hardware. Basic detection:
   model identifier, macOS version, T2 presence, bundled-data lookup. First captured
   fixture + `bats` tests.

3. **PCI vendor/device-id extraction.** The one genuinely hard part (§6.2): parse the
   little-endian byte arrays from `ioreg`, byte-swap, format as `1002:6819`. Isolated
   function with dedicated unit tests. Enables variant/component matching by PCI ID.

4. **Data loading tiers.** Resolution order cache → network (jsDelivr, pinned to a release
   tag) → bundled snapshot, with schema-validation on load and graceful offline fallback.
   Fetch **inert JSON only** — never remote code.

5. **Output modes + contribution funnel.** Finalise `--json` / `--markdown` / `--verbose`
   and the pre-filled GitHub issue URL for unknown models (with the ~8000-char fallback).

6. **Populate `iMac17,1` fully, then expand.** Fill remaining subsystems from verified
   observation, then add more 27" iMac identifiers.

## Companion tool: a Linux-side collector

**Goal:** a script that runs on **Linux** (for people who already installed it) and produces
the *same* structured hardware report as the macOS collector — same JSON shape, same PCI
`vendor:device` IDs.

Why it's worth building:

- **Grows the database from the other side.** Someone already running Linux on their iMac is
  the *best* source of verified data — they can see exactly what bound, at what kernel, with
  what caveats. Their report can feed the same `new-model` / `correction` issue funnel.
- **It can help them, not just us.** Matching their live hardware against the dataset lets
  the tool surface known fixes ("your GPU works but needs `nomodeset` removed", "this Wi-Fi
  needs the out-of-tree `wl` driver") for hardware that isn't working yet.
- **It closes the provenance loop.** macOS-side claims are predictions; Linux-side reports
  are direct observation — exactly what the `provenance` block with
  `verified_by: "direct observation on hardware"` is meant to capture.

Design notes / open questions (to refine when we get here):

- Reuse the macOS collector's output contract verbatim so both feed one issue template.
- Native Linux sources are richer and easier: `lspci -nn` gives `vendor:device` directly (no
  byte-swap), `/sys/class/dmi/id/product_name` is the model string that equals
  `sysctl hw.model`, `lsmod` / `Kernel driver in use:` shows what actually bound.
- Language: likely POSIX `sh`/`bash` to match the "no heavy deps" spirit; must degrade
  gracefully when `lspci` (pciutils) isn't installed.
- Could optionally emit a `provenance` block pre-filled with the live kernel
  (`uname -r`) and distro (`/etc/os-release`) — the fields that are guesswork from macOS.
- Same hard rule as the macOS tool: **read-only**, fetches inert JSON only, never executes
  remote content.

## Stretch goals (post-v1)

- Fold linux-hardware.org probe data in as an empirical layer beneath the hand-written
  notes. Their DB is indexed by DMI product name — the same string `sysctl hw.model` and
  `/sys/class/dmi/id/product_name` return. "34 of 37 probes show `wl` bound" is stronger than
  one person's recollection. Investigate after v1; not a launch dependency.
- Broaden scope beyond 27" iMacs (schema already allows it; don't build for it yet).
