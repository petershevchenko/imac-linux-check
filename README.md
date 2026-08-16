# imac-linux-check

A read-only macOS tool that reports an iMac's hardware and tells you what will and won't
work if you install Linux on it — **before** you commit to anything.

Apple ships a small number of fixed configurations per model, and the model identifier
(`iMac17,1`) is a near-perfect primary key. So this is a curated lookup table with a small
fallback path for build-to-order options — not a general hardware-matching engine. Scope at
launch is **27" iMacs**.

> **Status: early build.** The data schema, the validation pipeline, and the first verified
> model record (`iMac17,1`) are in place. The collector (`bin/imac-linux-check`) reads live
> hardware (or a captured fixture), detects the model, macOS version, T2 chip, and PCI
> vendor/device IDs, resolves build-to-order variants from those IDs, and loads data through
> a cache → CDN → bundled fallback (validated on load, works fully offline). Output modes and
> the unknown-model contribution link are next. See [`ROADMAP.md`](ROADMAP.md) for the plan.

## What makes it trustworthy

- **Data only, never code.** The tool will fetch inert JSON and nothing else — no remote
  code, no `eval`, no plugins. Data is schema-validated before use.
- **Read-only on your machine.** No writes outside `~/.cache/imac-linux-check/`. Safe to run
  on a machine still in production use.
- **Honest uncertainty.** `unknown` is a first-class status and is shown as such. Support is
  never inferred from a neighbouring model. If there's no verified record, it says so and
  invites a report.
- **Everything is dated.** Every support claim carries a `provenance` block (kernel, distro,
  date, source), because hardware support facts have a shelf life.

## Status values

Every component's Linux support is reported as exactly one of:

| Value | Meaning |
| --- | --- |
| `works` | Works out of the box on a current mainstream distro. |
| `works_with_caveats` | Functions, but with a documented limitation you should know about. |
| `works_with_workaround` | Requires a documented configuration change (kernel parameter, package install). |
| `needs_out_of_tree_driver` | Requires a DKMS or manually compiled driver. Secure Boot implications flagged. |
| `partial` | Some functions work, others do not. |
| `broken` | No working driver exists. |
| `unknown` | No verified data. Displayed honestly, never inferred. |

Results are reported **per subsystem**. There is deliberately no overall score or
"X% Linux-ready" verdict — an aggregate number ages badly and flattens the difference
between "the camera doesn't work" and "no Wi-Fi driver exists". You apply your own weighting.

## Repository layout

```
data/
  index.json          CI-generated manifest — never hand-edited
  models/             one file per Apple model identifier
  components/         one file per hardware component, referenced by ID
schema/               JSON Schema for model and component records
scripts/gen-index.py  regenerates data/index.json deterministically
tests/                data-integrity checks (schema, references, staleness)
```

One file per model and per component means two people adding different hardware never
produce a merge conflict, and component indirection keeps shared facts (identical audio or
Wi-Fi situations across generations) from drifting.

## Working on the data

```sh
# after editing anything under data/
python3 scripts/gen-index.py          # regenerate the index
python3 tests/test_data_integrity.py  # schema + referential integrity + staleness
```

CI runs the same checks on every pull request (`.github/workflows/validate.yml`).

## Licensing

The split is deliberate — see [`LICENSE`](LICENSE) and [`LICENSE-DATA`](LICENSE-DATA):

- **Code** (the collector, scripts, tests): **MIT**.
- **Data** (everything under `data/`): **CC0 1.0** (public domain dedication).

Please **do not copy prose** from the Arch/Debian/Gentoo wikis into the dataset — they are
copyleft-licensed and it creates a licensing problem that is hard to unpick. Link to them in
a record's `sources` and write the entry independently. See [`CONTRIBUTING.md`](CONTRIBUTING.md).
