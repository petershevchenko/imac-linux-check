# Handoff: `imac-linux-check`

A macOS-side tool that reports an iMac's hardware and tells the user what will and won't
work if they install Linux on it.

This document is the specification. It is written to be handed to Claude Code as the
starting brief for building the repository from scratch.

---

## 1. Purpose

Someone has an old iMac. They wonder whether Linux is viable on it. Today the only way to
find out is to search forums for their model, piece together contradictory posts of varying
ages, or just try it and discover the problems afterwards.

This tool runs on macOS, before they commit to anything, and answers the question.

### Why this is tractable

The obvious comparison is `hw-probe` (backs linux-hardware.org). That project is hard
because it must handle arbitrary PC hardware through general device-ID matching. It is
also Linux-only — a request to support macOS was closed as not planned, so this niche is
genuinely unfilled.

We have a much easier problem. Apple ships a small number of fixed configurations per
model, and the model identifier (`iMac17,1`) is a near-perfect primary key. Roughly 15–20
identifiers cover every 27" iMac from 2012 to 2020. This is a lookup table with a small
fallback path for build-to-order GPU options and user-replaced parts, not a general
matching engine.

### Non-goals

- Not a Linux installer, and not a bootloader configuration tool.
- Not a general Mac tool at launch. Scope is 27" iMacs. The schema should not *prevent*
  MacBooks or Mac minis later, but do not build for them now.
- Not a hardware benchmark.
- Does not modify the machine it runs on. It is strictly read-only. This is a hard rule.

---

## 2. Design principles

These are the constraints that matter. Everything else is negotiable.

### 2.1 Data-only, never code

The script fetches **JSON and nothing else** from the network. It must never fetch,
evaluate, or execute remote code — no remote shell fragments, no `eval` of downloaded
content, no plugin loading.

This is the single most important rule in the document. People will run this tool on a
machine they care about, and some will run it with `sudo`. A tool that pulls executable
content from a repo is a supply-chain vulnerability wearing a helpful costume. Fetching
only inert data that is then schema-validated before use keeps the blast radius at zero.

### 2.2 Data is separated from code, and lives in its own release cycle

Hardware support facts change independently of the collector logic. Somebody discovering
that a driver landed in a new kernel should be able to open a pull request against a JSON
file without touching a line of shell.

If the knowledge is hardcoded in the script, every fact update becomes a software release,
and the project dies the day its author gets bored. Separation is what makes outside
contribution possible.

### 2.3 Read-only on the host

No writes outside `~/.cache/imac-linux-check/`. No `nvram` writes, no `defaults write`, no
disk modification. The tool must be safe to run on a machine still in production use.

### 2.4 Honest uncertainty

`unknown` is a first-class status and must be displayed as such. A confident wrong answer
about whether someone's Wi-Fi will work is worse than admitting the data is missing. Never
infer a status from a neighbouring model — if there is no record, say so and invite a
report.

---

## 3. Repository layout

```
imac-linux-check/
├── README.md
├── LICENSE                       # MIT — applies to code
├── LICENSE-DATA                  # CC0 or CC-BY-SA — applies to data/
├── CONTRIBUTING.md
├── bin/
│   └── imac-linux-check          # the collector (zsh, no dependencies)
├── data/
│   ├── index.json                # CI-GENERATED. Never hand-edit.
│   ├── components/
│   │   ├── gpu-pci-1002-6819.json
│   │   ├── audio-cs8409.json
│   │   └── wifi-bcm4360.json
│   └── models/
│       ├── imac17-1.json
│       └── imac18-3.json
├── schema/
│   ├── component.schema.json
│   └── model.schema.json
├── tests/
│   ├── fixtures/
│   │   └── imac17-1/             # captured system_profiler + ioreg output
│   ├── test_collector.bats
│   └── test_data_integrity.py
└── .github/
    ├── workflows/
    │   ├── validate.yml
    │   └── release.yml
    └── ISSUE_TEMPLATE/
        └── new-model.yml
```

### Notes on the layout

**One file per model, one file per component.** Two people adding different models must
never produce a merge conflict. This matters more than it sounds — conflict-free
contribution is the difference between a repo that accumulates coverage and one that
doesn't.

**Component indirection avoids drift.** The CS8409 audio situation is identical across
several iMac generations. Written once in `components/`, referenced by ID from each model,
it stays consistent. Copy-pasted into six model files, the six copies diverge within a
year.

**Filenames normalise the comma.** `iMac17,1` becomes `imac17-1.json`. Commas in filenames
are legal but cause friction in URLs and shell quoting. The canonical identifier stays
intact inside the file.

---

## 4. Data model

### 4.1 Component record

```json
{
  "id": "gpu-pci-1002-6819",
  "category": "gpu",
  "name": "AMD Pitcairn PRO (Radeon R9 M380 / M390 class)",
  "match": {
    "pci": ["1002:6819"]
  },
  "linux": {
    "status": "works_with_caveats",
    "driver": "amdgpu",
    "driver_alternatives": ["radeon"],
    "kernel_min": "5.10",
    "firmware_package": "linux-firmware",
    "summary": "Binds automatically on modern kernels. Display Core initialises on DCE 6.0.",
    "caveats": [
      {
        "id": "no-backlight",
        "summary": "Panel brightness control is unavailable.",
        "detail": "amdgpu logs 'Skipping amdgpu DM backlight registration' on DCE 6.0.",
        "severity": "minor"
      }
    ],
    "workarounds": [
      {
        "problem": "No driver binds; only simpledrm is present and external outputs are absent.",
        "cause": "nomodeset on the kernel command line, commonly added to get the installer running.",
        "fix": "Remove nomodeset from GRUB_CMDLINE_LINUX_DEFAULT, then update-grub.",
        "kernel_params_remove": ["nomodeset"]
      },
      {
        "problem": "Older kernels bind the legacy radeon driver instead of amdgpu.",
        "fix": "Force Southern Islands to amdgpu.",
        "kernel_params_add": [
          "radeon.si_support=0",
          "radeon.cik_support=0",
          "amdgpu.si_support=1",
          "amdgpu.cik_support=1"
        ]
      }
    ]
  },
  "provenance": {
    "last_verified": "2026-07-24",
    "verified_kernel": "7.0.0-28-generic",
    "verified_distro": "Ubuntu 24.04",
    "verified_by": "direct observation on hardware",
    "sources": []
  }
}
```

### 4.2 Model record

```json
{
  "model_identifier": "iMac17,1",
  "marketing_name": "iMac (Retina 5K, 27-inch, Late 2015)",
  "screen_size_inches": 27,
  "native_resolution": "5120x2880",
  "components": [
    "gpu-pci-1002-6819",
    "wifi-bcm4360"
  ],
  "variants": [
    {
      "description": "Build-to-order Radeon R9 M395 / M395X",
      "distinguish_by": { "pci": ["1002:6938"] },
      "components_replace": { "gpu-pci-1002-6819": "gpu-pci-1002-6938" }
    }
  ],
  "model_notes": [],
  "provenance": { }
}
```

### 4.3 Status enum

Use exactly these values. Do not invent more without updating the schema and the README
table that explains them to users.

| Value | Meaning |
| --- | --- |
| `works` | Works out of the box on a current mainstream distro. |
| `works_with_caveats` | Functions, but with a documented limitation the user should know about. |
| `works_with_workaround` | Requires a documented configuration change (kernel parameter, package install). |
| `needs_out_of_tree_driver` | Requires a DKMS or manually compiled driver. Flag Secure Boot implications. |
| `partial` | Some functions work, others do not. |
| `broken` | No working driver exists. |
| `unknown` | No verified data. Must be displayed honestly, never inferred. |

### 4.4 Provenance — the fields that stop the data rotting

**Every** support claim carries a `provenance` block. This is not optional and the schema
must enforce it:

- `last_verified` — ISO date
- `verified_kernel` — exact kernel version string
- `verified_distro` — distribution and release
- `verified_by` — `"direct observation on hardware"` or `"third-party report"`
- `sources` — array of URLs

Hardware support facts have a shelf life. A concrete example from this project's own
origin: on this hardware, `amdgpu` now binds Pitcairn automatically, which was not true a
few kernel generations ago and required explicit `si_support` parameters. Anyone reading an
undated claim cannot tell whether it still holds.

A stale claim with no date attached is worse than no claim, because the reader has no way
to discount it.

CI must warn (not fail) on any record whose `last_verified` is more than 24 months old, and
the collector must surface record age in verbose output.

---

## 5. Distribution and offline behaviour

### 5.1 Fetch through a CDN, pinned to a tag

Do **not** fetch from `raw.githubusercontent.com`. It is rate-limited and not intended as a
delivery endpoint. Use jsDelivr's GitHub passthrough:

```
https://cdn.jsdelivr.net/gh/<owner>/imac-linux-check@v1/data/models/imac17-1.json
```

**Pin to a release tag, never to `main`.** If the script tracks `main`, a single bad merge
instantly breaks the tool for every user in the world. A tag means releases are cut
deliberately. The pinned tag lives in one constant at the top of the script.

### 5.2 Offline fallback

Every script release vendors a snapshot of `data/` alongside it. Resolution order:

1. Local cache in `~/.cache/imac-linux-check/`, if fresher than 24 hours
2. Network fetch from the pinned CDN tag
3. Bundled snapshot

The tool must produce a useful answer with no network at all — someone assessing a machine
that isn't online still gets a result, with a clear "data snapshot is N months old"
warning. Never fail hard on network unavailability.

### 5.3 Validate on load

Schema-validate fetched data before using it, and fall back to the bundled snapshot if
validation fails. This closes the gap where a malformed or tampered file causes the script
to misbehave.

---

## 6. The collector script

Single-file `zsh`, no dependencies. **Do not use Python.** macOS ships zsh as the default
shell and always has it; `python3` requires Command Line Tools that a curious non-developer
will not have installed. The whole point is that a novice can run one command.

### 6.1 Data sources on macOS

```sh
system_profiler -json \
    SPHardwareDataType SPDisplaysDataType SPAirPortDataType \
    SPAudioDataType SPStorageDataType SPNVMeDataType \
    SPSerialATADataType SPBluetoothDataType SPThunderboltDataType \
    SPCameraDataType SPiBridgeDataType SPMemoryDataType

sysctl hw.model            # same string Linux reports as DMI product name
sw_vers
```

`SPiBridgeDataType` returning anything means a T2 security chip is present. That single
fact changes the entire answer for 2020 models and must be checked early and prominently —
route those users to the t2linux project.

### 6.2 PCI vendor/device ID extraction — the one hard part

Everything else is a JSON field lookup. This is the piece that needs real work, and it
matters because PCI IDs are what make results comparable to `lspci -nn` output and to
existing Linux compatibility databases.

IDs live in the IORegistry as little-endian byte arrays:

```sh
ioreg -l -p IOService | grep -E '"(vendor|device)-id"'
```

Output resembles `"vendor-id" = <02100000>`, which is `0x1002` byte-swapped. The script must
parse the hex blob, take the first four bytes, byte-swap, and format as `1002:6819`.

Write this as a small isolated function with dedicated unit tests. It is the highest-risk
code in the project and the easiest to get subtly wrong.

### 6.3 Output modes

- **default** — coloured terminal summary, per-subsystem
- `--markdown` — for pasting into forum posts and issues
- `--json` — machine-readable, and the payload for the issue template
- `--verbose` — includes provenance dates and raw detected IDs
- `--offline` — skip network, use bundled data
- `--fixture-dir DIR` — read captured tool output instead of live hardware (see testing)

### 6.4 Presentation decision

Report **per-subsystem status with a short summary line, and no overall score or verdict.**

The temptation is a headline grade — "this machine is 70% Linux-ready". Resist it. An
aggregate number is the part that ages worst, that people argue about in issues, and that
flattens the distinction between "the camera doesn't work" (irrelevant to most) and "no
Wi-Fi driver exists" (disqualifying for many). Per-subsystem status lets the reader apply
their own weighting.

*This was flagged as a decision for the repo owner to confirm before implementation.*

---

## 7. Testing

### 7.1 The fixture approach — the key testability decision

Capture real `system_profiler -json` and `ioreg` output into `tests/fixtures/<model>/` and
have the collector accept `--fixture-dir` to read from there instead of live hardware.

This makes the entire tool testable in CI on Linux runners without any Apple hardware. It
also means every new model report contributed via an issue can become a permanent
regression fixture. Build this in from the first commit — retrofitting it later means
restructuring every I/O call in the script.

### 7.2 Test layers

**Shell** — `shellcheck` on the collector, plus `bats-core` tests running against fixtures.
Cover at minimum: PCI ID byte-swapping, T2 detection, unknown-model handling, all output
modes, and offline fallback.

**Data integrity** (Python, run in CI):
- JSON Schema validation of every file in `data/`
- Referential integrity: every component ID referenced by a model exists
- No orphan components (warn only)
- `index.json` matches the actual directory contents
- Every record has a complete `provenance` block
- Staleness warning at 24 months

**Round-trip** — for each fixture, run the collector and assert the resulting JSON matches
a stored expected output. Catches unintended changes to detection logic.

---

## 8. CI

### `validate.yml` — on every PR

1. `shellcheck bin/imac-linux-check`
2. Schema-validate all data files (`check-jsonschema` or `ajv-cli`)
3. Referential integrity checks
4. `bats` tests against fixtures
5. Regenerate `index.json` and fail if it differs from the committed version

Without automatic validation the schema is decorative and the maintainer's time goes into
correcting formatting in pull requests — which is precisely the drudgery that kills
volunteer projects. This workflow is not a nice-to-have; build it in the first milestone.

### `release.yml` — on tag

Bundle the data snapshot into the script release, publish the GitHub release, verify the
jsDelivr URL for the new tag resolves.

---

## 9. Contribution flow

`CONTRIBUTING.md` should make the low-friction path obvious.

### The mechanism that gets coverage of models you don't own

When the collector encounters an unknown model, it prints a **pre-filled GitHub issue
URL**. GitHub accepts `?title=...&body=...` query parameters on
`/issues/new`, so the user's full hardware dump can be URL-encoded into the link.

Someone with an iMac13,2 runs the script, gets "unknown model", and one click later there
is a structured issue containing everything needed to write the record. This is the
difference between a database covering the maintainer's machines and one covering the
fleet.

Watch the URL length limit — if the encoded body would exceed roughly 8000 characters,
print the JSON to stdout and instruct the user to paste it instead.

### Issue templates

- `new-model.yml` — structured form, with a field for pasted `--json` output
- `correction.yml` — for "this is now fixed in kernel X", requiring kernel version, distro,
  and date

---

## 10. Licensing

- **Code: MIT.** `LICENSE`.
- **Data: CC0 (preferred) or CC-BY-SA.** `LICENSE-DATA`. State the split explicitly in the
  README.

This matters more than it looks. The Arch Wiki, Debian Wiki, and Gentoo Wiki are the
obvious sources for this kind of knowledge, and they are copyleft-licensed. **Do not copy
text from them.** Link to them in `sources`, and write the entry independently. Copying
wiki prose into a CC0 dataset creates a licensing problem that is very hard to unpick once
contributors have built on top of it.

Add a note to `CONTRIBUTING.md` telling contributors the same thing.

---

## 11. Seed data — verified iMac17,1 record

This is real, directly observed data. Use it as the reference model file, and as the
worked example for the schema.

**Machine:** iMac17,1, 27" Retina 5K, Late 2015. Ubuntu 24.04, kernel 7.0.0-28-generic,
booted UEFI. Verified 2026-07-24.

**GPU** — AMD Pitcairn PRO, PCI `1002:6819`, Apple subsystem `106b:014e` (R9 M380/M390
class, GCN 1.0 / Southern Islands).

- `amdgpu` binds automatically on kernel 7.0; no `si_support` parameters needed
- Reports: `Display Core v3.2.369 initialized on DCE 6.0`, 2048 MB GDDR5, 256-bit
- Connectors exposed: `eDP-1`, `DP-1`, `DP-2`, `DP-3`
- **Critical gotcha:** `nomodeset` on the kernel command line results in no DRM driver
  binding at all — only `simpledrm` with a `card0-Unknown-1` connector, no external
  outputs, no hotplug. Installers commonly add it. Removing it is the fix. `lspci -nnk`
  showing no `Kernel driver in use:` line is the diagnostic signature.
- Backlight control unavailable: `Skipping amdgpu DM backlight registration`

**Display topology** — worth recording precisely, since it is confusing and widely
misreported:

- `eDP-1` — internal 5K panel, primary link
- `DP-1` — internal panel's *second* link, reported disconnected in single-link operation
- `DP-2`, `DP-3` — the two external Thunderbolt 2 / Mini DisplayPort ports

**5K resolution — does not work on this model.** The panel is 5120x2880 but only
3840x2160 is available under Linux. The internal display needs two DisplayPort channels for
5120x2880@60; one channel suffices for 3840x2160@60 and below.

The EDID contains a CTA-861 extension but **no DisplayID tile block**, so the mode is never
advertised — this is not kernel mode pruning, and nothing appears in dmesg about pruning.
Forcing it via `video=eDP-1:5120x2880@60` produces:

```
amdgpu: [drm] User-defined mode not supported: "5120x2880": 60 1275624 ...
```

The bandwidth analysis: DCE 6.0 is DisplayPort 1.2, so a link caps at HBR2 — 4 lanes ×
5.4 Gbps = 21.6 Gbps raw, roughly 17.28 Gbps of payload after 8b/10b encoding, which is
about 720 MHz of pixel clock at 24bpp. Even reduced-blanking 5K60 needs about 938 MHz.
It does not fit.

**Important for the database:** widely circulated forum advice recommends
`amdgpu.dc=1 amdgpu.mst=1 video=eDP-1:5120x2880@60` for 5K on iMacs. Those reports come
from **2017 and 2019 models with Polaris GPUs (DisplayPort 1.4 / HBR3, 32.4 Gbps)**, where
5K60 fits on one link. Applying that advice to a DCE 6.0 machine does not work. The
component record should capture this distinction explicitly, because it is exactly the kind
of thing users will file incorrect issues about.

**External display** — Mini DisplayPort to DisplayPort, passive cable, works at 3840x2160.

---

## 12. Subsystems the database must cover

Ordered roughly by how often they determine whether Linux is viable:

| Subsystem | Why it matters |
| --- | --- |
| Wi-Fi | Broadcom BCM43xx, out-of-tree `wl` driver, DKMS, hostile to Secure Boot. The most common dealbreaker. |
| GPU / display | Driver binding, `nomodeset`, panel resolution limits, backlight. Nvidia Kepler models are the worst case — nouveau performs poorly and legacy proprietary drivers have aged out of current kernels. |
| Audio | Cirrus Logic CS8409 on 2017+ models. Upstream driver's quirk table is Dell-only; the out-of-tree driver was broken by the kernel 6.17/7.0 HDA subsystem refactor. |
| T2 chip | 2020 models. Affects keyboard, trackpad, audio, and SSD. Effectively a separate project — link to t2linux. |
| Fan control | `applesmc` / `mbpfan`. iMacs genuinely overheat without it. Easy to overlook and important. |
| Storage | Fusion Drive presents as two devices; proprietary Apple SSD connectors on some generations. |
| Camera | `facetimehd` for pre-2015 models. |
| Bluetooth | Firmware extraction needed on some models. |
| Boot | UEFI quirks, `bless`, rEFInd. |

---

## 13. Build order

1. **Schema + validation CI + one hand-written model file.** Nothing else. Get the
   validation loop working before there is data to migrate.
2. **Collector skeleton with `--fixture-dir` and one captured fixture.** Establish the
   testable I/O boundary before adding detection logic.
3. **PCI ID extraction** with unit tests.
4. **Data loading**: bundled → cache → network, with schema validation on load.
5. **Output modes**, then the pre-filled issue URL.
6. **Populate iMac17,1 fully** from section 11, then expand outward.

Start narrower than the ambition. A tool that is confidently right about five models is
more useful, and more trustworthy, than one that is vaguely right about twenty.

---

## 14. Open decisions for the repo owner

- Repository name and owner (needed for the jsDelivr URL constant).
- Data license: CC0 or CC-BY-SA.
- Confirm the no-overall-verdict decision in section 6.4.
- Whether to query linux-hardware.org by model identifier and fold real probe data in as an
  empirical layer beneath the hand-written notes. Their database is indexed by DMI product
  name, which is the same string `sysctl hw.model` returns. "34 of 37 probes for this model
  show `wl` bound" is stronger evidence than one person's recollection. Worth investigating
  after v1 — treat as a stretch goal, not a launch dependency.
