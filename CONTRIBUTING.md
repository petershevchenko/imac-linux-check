# Contributing

The most valuable contribution is **verified hardware data**: a model or component record
for a machine you have actually run Linux on.

## The rules that keep the dataset healthy

1. **One file per model, one file per component.** Add `data/models/<model>.json` and/or
   `data/components/<id>.json`. Never edit someone else's model file to add yours — that is
   what causes merge conflicts. Reference shared components by ID instead of copying them.

2. **Never hand-edit `data/index.json`.** It is generated. Run `python3 scripts/gen-index.py`
   and commit the result.

3. **Every support claim needs provenance.** Fill in `last_verified`, `verified_by`, and
   (for direct observations) `verified_kernel` and `verified_distro`. The schema enforces
   this. An undated claim is worse than no claim, because a reader can't discount it.

4. **`unknown` is honest, inference is not.** If you have not verified a component, mark it
   `unknown` — do not guess its status from a similar model. A wrong "it works" is worse than
   an admitted gap.

5. **Do not copy prose from wikis.** The Arch, Debian, and Gentoo wikis are copyleft. Copying
   their text into this CC0 dataset creates a licensing problem. Link them under `sources` and
   write the entry in your own words.

## Before you open a pull request

```sh
python3 scripts/gen-index.py            # regenerate the index
python3 tests/test_data_integrity.py    # must pass
```

Both run in CI (`.github/workflows/validate.yml`) along with `check-jsonschema` against the
schemas. If they pass locally, the PR should be green.

## Filenames

`iMac17,1` becomes `imac17-1.json` — lowercase, comma to hyphen. The canonical identifier
with the comma stays intact inside the file (`"model_identifier": "iMac17,1"`). Component
filenames match their `id` exactly (`gpu-pci-1002-6819.json` ⟷ `"id": "gpu-pci-1002-6819"`).
