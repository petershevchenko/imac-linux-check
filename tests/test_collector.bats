#!/usr/bin/env bats
#
# Collector tests. Run against captured fixtures, so no Apple hardware is needed.
#   bats tests/test_collector.bats
# Requires zsh (the collector's interpreter) and jq (the Linux JSON engine).

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  COLLECTOR="$ROOT/bin/imac-linux-check"
  FIX="$ROOT/tests/fixtures"
  # Isolate the cache and point the CDN at a non-existent file:// tree so the
  # default (online) tests fall back to bundled data instantly, with no real
  # network call. Individual tier tests below override IMAC_LC_CDN_BASE.
  export IMAC_LC_CACHE_DIR="$BATS_TEST_TMPDIR/cache"
  export IMAC_LC_CDN_BASE="file://$BATS_TEST_TMPDIR/no-such-cdn"
}

@test "--version prints the version" {
  run "$COLLECTOR" --version
  [ "$status" -eq 0 ]
  [ "$output" = "0.5.0-dev" ]
}

@test "--help exits 0 and states the read-only guarantee" {
  run "$COLLECTOR" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"read-only"* ]]
}

@test "known model: identifies iMac17,1 and its marketing name" {
  run "$COLLECTOR" --fixture-dir "$FIX/imac17-1" --no-color
  [ "$status" -eq 0 ]
  [[ "$output" == *"iMac17,1"* ]]
  [[ "$output" == *"Retina 5K"* ]]
}

@test "known model: lists gpu and wifi subsystem statuses" {
  run "$COLLECTOR" --fixture-dir "$FIX/imac17-1" --no-color
  [[ "$output" == *"gpu"*"works_with_caveats"* ]]
  [[ "$output" == *"wifi"*"unknown"* ]]
}

@test "known model: T2 reported absent" {
  run "$COLLECTOR" --fixture-dir "$FIX/imac17-1" --no-color
  [[ "$output" == *"T2 chip:"*"no"* ]]
}

@test "--json is valid and reports a known model with two subsystems" {
  run "$COLLECTOR" --fixture-dir "$FIX/imac17-1" --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e . >/dev/null
  [ "$(echo "$output" | jq -r '.model_identifier')" = "iMac17,1" ]
  [ "$(echo "$output" | jq -r '.model_known')" = "true" ]
  [ "$(echo "$output" | jq -r '.subsystems | length')" = "2" ]
}

@test "--markdown emits a table" {
  run "$COLLECTOR" --fixture-dir "$FIX/imac17-1" --markdown
  [ "$status" -eq 0 ]
  [[ "$output" == *"| Field | Value |"* ]]
  [[ "$output" == *"### Subsystems"* ]]
}

@test "unknown model: says so and does not invent a status" {
  run "$COLLECTOR" --fixture-dir "$FIX/unknown-model" --no-color
  [ "$status" -eq 0 ]
  [[ "$output" == *"not in the database"* ]]
  [[ "$output" == *"iMac13,2"* ]]
}

@test "T2 machine: detected and routed to t2linux" {
  run "$COLLECTOR" --fixture-dir "$FIX/imac-t2" --no-color
  [ "$status" -eq 0 ]
  [[ "$output" == *"T2 security chip detected"* ]]
  [[ "$output" == *"t2linux.org"* ]]
}

@test "missing fixture dir is a usage error" {
  run "$COLLECTOR" --fixture-dir /no/such/dir
  [ "$status" -eq 2 ]
}

@test "unknown flag is a usage error" {
  run "$COLLECTOR" --bogus
  [ "$status" -eq 2 ]
}

@test "read-only: running does not write into the fixture dir" {
  before="$(find "$FIX/imac17-1" -type f | sort)"
  run "$COLLECTOR" --fixture-dir "$FIX/imac17-1" --json
  after="$(find "$FIX/imac17-1" -type f | sort)"
  [ "$before" = "$after" ]
}

# --- PCI id extraction (spec §6.2), the highest-risk code ------------------

@test "pci_swap_id byte-swaps little-endian blobs" {
  [ "$("$COLLECTOR" __pci-swap 02100000)" = "1002" ]
  [ "$("$COLLECTOR" __pci-swap 19680000)" = "6819" ]
  [ "$("$COLLECTOR" __pci-swap e4140000)" = "14e4" ]
  [ "$("$COLLECTOR" __pci-swap a0430000)" = "43a0" ]
  [ "$("$COLLECTOR" __pci-swap 38690000)" = "6938" ]
}

@test "pci_swap_id accepts angle brackets and uppercase, tolerates short blobs" {
  [ "$("$COLLECTOR" __pci-swap '<02100000>')" = "1002" ]
  [ "$("$COLLECTOR" __pci-swap 0210)" = "1002" ]
  [ "$("$COLLECTOR" __pci-swap 'AB CD 00 00')" = "cdab" ]
}

@test "pci_swap_id rejects non-hex / too-short input" {
  run "$COLLECTOR" __pci-swap "xyzq"
  [ "$status" -ne 0 ]
  run "$COLLECTOR" __pci-swap ""
  [ "$status" -ne 0 ]
}

@test "extract_pci_ids pairs vendor:device per node, ignoring subsystem ids" {
  run "$COLLECTOR" __pci-extract < "$FIX/imac17-1/ioreg.txt"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "1002:6819" ]
  [ "${lines[1]}" = "14e4:43a0" ]
  [ "${#lines[@]}" -eq 2 ]
}

# --- variant detection by PCI id -------------------------------------------

@test "base config: no variant, keeps the base GPU component" {
  run "$COLLECTOR" --fixture-dir "$FIX/imac17-1" --json
  [ "$(echo "$output" | jq -r '.variant')" = "null" ]
  [ "$(echo "$output" | jq -r '.detected_pci[0]')" = "1002:6819" ]
  [ "$(echo "$output" | jq -r '.subsystems[] | select(.category=="gpu") | .id')" = "gpu-pci-1002-6819" ]
}

@test "M395 BTO GPU: variant matched, GPU component swapped" {
  run "$COLLECTOR" --fixture-dir "$FIX/imac17-1-m395" --no-color
  [[ "$output" == *"Variant:"*"M395"* ]]
  run "$COLLECTOR" --fixture-dir "$FIX/imac17-1-m395" --json
  [ "$(echo "$output" | jq -r '.detected_pci[0]')" = "1002:6938" ]
  [ "$(echo "$output" | jq -r '.subsystems[] | select(.category=="gpu") | .id')" = "gpu-pci-1002-6938" ]
  [ "$(echo "$output" | jq -r '.subsystems[] | select(.category=="gpu") | .status')" = "unknown" ]
}

# --- data loading tiers: cache -> network -> bundled -----------------------

# Build a fake CDN tree whose iMac17,1 record has a marker marketing name.
make_fake_cdn() {
  local dir="$1" name="$2"
  mkdir -p "$dir/data/models"
  jq --arg n "$name" '.marketing_name = $n' \
    "$ROOT/data/models/imac17-1.json" > "$dir/data/models/imac17-1.json"
}

@test "offline: falls back to bundled data and reports the snapshot" {
  run "$COLLECTOR" --fixture-dir "$FIX/imac17-1" --offline --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.data_source')" = "bundled" ]
  [ "$(echo "$output" | jq -r '.marketing_name')" = "iMac (Retina 5K, 27-inch, Late 2015)" ]
}

@test "network tier: fetches from the CDN, then serves from fresh cache" {
  cdn="$BATS_TEST_TMPDIR/cdn"
  make_fake_cdn "$cdn" "FETCHED-FROM-CDN"
  export IMAC_LC_CDN_BASE="file://$cdn"

  run "$COLLECTOR" --fixture-dir "$FIX/imac17-1" --json
  [ "$(echo "$output" | jq -r '.data_source')" = "network" ]
  [ "$(echo "$output" | jq -r '.marketing_name')" = "FETCHED-FROM-CDN" ]

  # cache is now fresh — second run must not re-fetch
  run "$COLLECTOR" --fixture-dir "$FIX/imac17-1" --json
  [ "$(echo "$output" | jq -r '.data_source')" = "cache" ]
  [ "$(echo "$output" | jq -r '.marketing_name')" = "FETCHED-FROM-CDN" ]
}

@test "validate-on-load: a malformed CDN file is rejected for bundled" {
  cdn="$BATS_TEST_TMPDIR/cdn"
  mkdir -p "$cdn/data/models"
  printf '{ not valid json ' > "$cdn/data/models/imac17-1.json"
  export IMAC_LC_CDN_BASE="file://$cdn"

  run "$COLLECTOR" --fixture-dir "$FIX/imac17-1" --json
  [ "$(echo "$output" | jq -r '.data_source')" = "bundled" ]
  [ "$(echo "$output" | jq -r '.marketing_name')" = "iMac (Retina 5K, 27-inch, Late 2015)" ]
}

@test "offline never fetches, even when the CDN has content" {
  cdn="$BATS_TEST_TMPDIR/cdn"
  make_fake_cdn "$cdn" "SHOULD-NOT-APPEAR"
  export IMAC_LC_CDN_BASE="file://$cdn"

  run "$COLLECTOR" --fixture-dir "$FIX/imac17-1" --offline --json
  [ "$(echo "$output" | jq -r '.data_source')" = "bundled" ]
  [ "$(echo "$output" | jq -r '.marketing_name')" = "iMac (Retina 5K, 27-inch, Late 2015)" ]
}

# --- contribution funnel: pre-filled issue for unknown models --------------

@test "unknown model: prints a pre-filled issue URL for this repo" {
  run "$COLLECTOR" --fixture-dir "$FIX/unknown-model" --offline --no-color
  [ "$status" -eq 0 ]
  [[ "$output" == *"github.com/petershevchenko/imac-linux-check/issues/new"* ]]
  [[ "$output" == *"title=Add%20model%3A%20iMac13%2C2"* ]]
}

@test "unknown model: issue URL body round-trips to the JSON dump" {
  run "$COLLECTOR" --fixture-dir "$FIX/unknown-model" --offline --no-color
  url="$(printf '%s\n' "$output" | grep -o 'https://[^ ]*issues/new[^ ]*')"
  [ -n "$url" ]
  body="$(printf '%s' "${url#*&body=}")"
  decoded="$(printf '%b' "${body//%/\\x}")"
  [[ "$decoded" == *'"model_identifier": "iMac13,2"'* ]]
  [[ "$decoded" == *'"10de:11a0"'* ]]
}

@test "unknown model: oversized dump falls back to print-and-paste" {
  export IMAC_LC_ISSUE_MAX_URL=100
  run "$COLLECTOR" --fixture-dir "$FIX/unknown-model" --offline --no-color
  [ "$status" -eq 0 ]
  [[ "$output" == *"template=new-model.yml"* ]]
  [[ "$output" == *"paste this JSON"* ]]
  [[ "$output" == *'"model_identifier": "iMac13,2"'* ]]
}

@test "markdown for an unknown model links to the report" {
  run "$COLLECTOR" --fixture-dir "$FIX/unknown-model" --offline --markdown
  [[ "$output" == *"[Add this model]("* ]]
  [[ "$output" == *"issues/new"* ]]
}
