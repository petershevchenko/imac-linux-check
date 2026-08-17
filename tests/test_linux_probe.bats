#!/usr/bin/env bats
#
# Tests for the Linux-side collector. Run against captured lspci/dmi fixtures,
# so no real iMac hardware is needed. Requires bash and jq.
#   bats tests/test_linux_probe.bats

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  PROBE="$ROOT/bin/imac-linux-probe"
  FIX="$ROOT/tests/fixtures"
}

@test "--version prints the version" {
  run "$PROBE" --version
  [ "$status" -eq 0 ]
  [ "$output" = "0.1.0-dev" ]
}

@test "--help states the read-only guarantee" {
  run "$PROBE" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Read-only"* ]]
}

@test "reports model, kernel and distro" {
  run "$PROBE" --fixture-dir "$FIX/linux-imac17-1" --no-color
  [ "$status" -eq 0 ]
  [[ "$output" == *"iMac17,1"* ]]
  [[ "$output" == *"6.8.0-45-generic"* ]]
  [[ "$output" == *"Ubuntu 24.04.1 LTS"* ]]
}

@test "detects live drivers and cross-references the dataset" {
  run "$PROBE" --fixture-dir "$FIX/linux-imac17-1" --no-color
  [[ "$output" == *"gpu"*"1002:6819"*"amdgpu"*"works_with_caveats"* ]]
  [[ "$output" == *"wifi"*"14e4:43a0"*"wl"*"needs_out_of_tree_driver"* ]]
}

@test "--json carries a direct-observation provenance block" {
  run "$PROBE" --fixture-dir "$FIX/linux-imac17-1" --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e . >/dev/null
  [ "$(echo "$output" | jq -r '.provenance.verified_by')" = "direct observation on hardware" ]
  [ "$(echo "$output" | jq -r '.provenance.verified_kernel')" = "6.8.0-45-generic" ]
  [ "$(echo "$output" | jq -r '.provenance.verified_distro')" = "Ubuntu 24.04.1 LTS" ]
}

@test "--json marks a known component with its bound driver and dataset status" {
  run "$PROBE" --fixture-dir "$FIX/linux-imac17-1" --json
  wifi="$(echo "$output" | jq -c '.devices[] | select(.category=="wifi")')"
  [ "$(echo "$wifi" | jq -r '.driver')" = "wl" ]
  [ "$(echo "$wifi" | jq -r '.bound')" = "true" ]
  [ "$(echo "$wifi" | jq -r '.dataset_component')" = "wifi-bcm4360" ]
  [ "$(echo "$wifi" | jq -r '.dataset_status')" = "needs_out_of_tree_driver" ]
}

@test "an unbound device is reported as not bound" {
  run "$PROBE" --fixture-dir "$FIX/linux-imac17-1-nowifi" --json
  wifi="$(echo "$output" | jq -c '.devices[] | select(.category=="wifi")')"
  [ "$(echo "$wifi" | jq -r '.driver')" = "none" ]
  [ "$(echo "$wifi" | jq -r '.bound')" = "false" ]
}

@test "prints a pre-filled report URL with direct-observation body" {
  run "$PROBE" --fixture-dir "$FIX/linux-imac17-1" --no-color
  url="$(printf '%s\n' "$output" | grep -o 'https://[^ ]*issues/new[^ ]*')"
  [ -n "$url" ]
  [[ "$url" == *"github.com/petershevchenko/imac-linux-check/issues/new"* ]]
  body="$(printf '%s' "${url#*&body=}")"
  decoded="$(printf '%b' "${body//%/\\x}")"
  [[ "$decoded" == *"direct observation on hardware"* ]]
  [[ "$decoded" == *'"driver": "wl"'* ]]
}

@test "--markdown emits a device table" {
  run "$PROBE" --fixture-dir "$FIX/linux-imac17-1" --markdown
  [[ "$output" == *"| Subsystem | PCI id | Bound driver | Dataset status |"* ]]
  [[ "$output" == *"amdgpu"* ]]
}

@test "missing fixture dir is a usage error" {
  run "$PROBE" --fixture-dir /no/such/dir
  [ "$status" -eq 2 ]
}

@test "read-only: running does not write into the fixture dir" {
  before="$(find "$FIX/linux-imac17-1" -type f | sort)"
  run "$PROBE" --fixture-dir "$FIX/linux-imac17-1" --json
  after="$(find "$FIX/linux-imac17-1" -type f | sort)"
  [ "$before" = "$after" ]
}
