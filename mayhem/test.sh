#!/usr/bin/env bash
# Runs wabt's own functional suites (built by mayhem/build.sh with normal flags): the golden-output
# test/run-tests.py suite (wat2wasm, wasm2wat, wasm-objdump, wasm-interp, spec tests, ...) and the
# gtest unit tests. Every case asserts tool output against an expected value.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

BIN="$SRC/build/tests"
for t in wat2wasm wasm2wat wasm-objdump wasm-interp spectest-interp wasm2c wabt-unittests; do
  [ -x "$BIN/$t" ] || { echo "missing $BIN/$t: mayhem/build.sh must build the test tools" >&2; exit 1; }
done

LOG="$(mktemp)"
python3 test/run-tests.py --bindir "$BIN" -j "$MAYHEM_JOBS" >"$LOG" 2>&1
rc=$?
passed=$(grep -c '^+ ' "$LOG")
skipped=$(grep -c '^\. ' "$LOG")
failed=$(awk '/^\*\*\*\* FAILED/ {exit} /^- / {n++} END {print n+0}' "$LOG")
[ "$rc" -eq 0 ] || [ "$failed" -gt 0 ] || failed=1
if [ "$failed" -gt 0 ]; then grep -A3 '^- ' "$LOG" | head -60 >&2; fi

UT="$(mktemp)"
"$BIN/wabt-unittests" >"$UT" 2>&1
ut_rc=$?
ut_passed=$(sed -n 's/^\[  PASSED  \] \([0-9]*\) test.*/\1/p' "$UT" | tail -1)
ut_failed=$(sed -n 's/^\[  FAILED  \] \([0-9]*\) test.*/\1/p' "$UT" | tail -1)
passed=$(( passed + ${ut_passed:-0} ))
failed=$(( failed + ${ut_failed:-0} ))
if [ "$ut_rc" -ne 0 ] && [ -z "${ut_failed:-}" ]; then failed=$(( failed + 1 )); tail -20 "$UT" >&2; fi

emit_ctrf "wabt-run-tests+gtest" "$passed" "$failed" "$skipped"
