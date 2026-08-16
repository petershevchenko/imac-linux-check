#!/usr/bin/env bats
#
# Collector tests. Run against captured fixtures, so no Apple hardware is needed.
#   bats tests/test_collector.bats
# Requires zsh (the collector's interpreter) and jq (the Linux JSON engine).

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  COLLECTOR="$ROOT/bin/imac-linux-check"
  FIX="$ROOT/tests/fixtures"
}

@test "--version prints the version" {
  run "$COLLECTOR" --version
  [ "$status" -eq 0 ]
  [ "$output" = "0.3.0-dev" ]
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
