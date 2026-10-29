#!/usr/bin/env bash
# Builds (1) the sanitized libwabt + the six libFuzzer harnesses (+ -standalone reproducers) and
# (2) the project's normal-flag tools used by mayhem/test.sh. Re-runnable and offline.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

# upstream's third_party/ submodules (simde, picosha2, gtest, testsuite) must already be checked out
for d in simde picosha2 gtest testsuite; do
  [ -n "$(ls -A "third_party/$d" 2>/dev/null)" ] || { echo "third_party/$d is empty: git submodule update --init" >&2; exit 1; }
done

# 1) sanitized library (the fuzzed code), DWARF 3
cmake -S . -B build/fuzz -G Ninja \
  -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
  -DCMAKE_BUILD_TYPE= \
  -DCMAKE_C_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS -O1" \
  -DCMAKE_CXX_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS -O1" \
  -DBUILD_TESTS=OFF -DBUILD_TOOLS=OFF -DBUILD_LIBWASM=OFF -DWABT_INSTALL_RULES=OFF \
  -DUSE_INTERNAL_SHA256=ON
cmake --build build/fuzz -j"$MAYHEM_JOBS" --target wabt

# 2) harnesses: libFuzzer binary + run-once standalone reproducer, both with LSan switched off
mkdir -p build/obj
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o build/obj/standalone_main.o
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c mayhem/lsan_off.cc -o build/obj/lsan_off.o
# binary-reader-objdump.cc is compiled into the wasm-objdump tool upstream, not into libwabt
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -O1 -std=c++20 -Iinclude -Ibuild/fuzz/include \
  -c src/binary-reader-objdump.cc -o build/obj/binary-reader-objdump.o
for h in read_binary_interp_fuzzer read_binary_ir_fuzzer wasm2wat_fuzzer wasm_objdump_fuzzer wat2wasm_fuzzer wasm_interp_fuzzer; do
  src=fuzzers/$h.cc; [ -f "$src" ] || src=mayhem/$h.cc      # wasm_interp_fuzzer lives only in OSS-Fuzz's project dir
  extra=""; [ "$h" != wasm_objdump_fuzzer ] || extra=build/obj/binary-reader-objdump.o
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS -O1 -std=c++20 -Iinclude -Ibuild/fuzz/include \
    $src $extra build/obj/lsan_off.o build/fuzz/libwabt.a $LIB_FUZZING_ENGINE -o /mayhem/$h
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS -O1 -std=c++20 -Iinclude -Ibuild/fuzz/include \
    $src $extra build/obj/standalone_main.o build/obj/lsan_off.o build/fuzz/libwabt.a -o /mayhem/$h-standalone
done

# 3) the upstream test tools with the project's NORMAL flags (clean, independent build)
env -u CFLAGS -u CXXFLAGS cmake -S . -B build/tests -G Ninja \
  -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_FLAGS="$COVERAGE_FLAGS" -DCMAKE_CXX_FLAGS="$COVERAGE_FLAGS" \
  -DBUILD_TESTS=ON -DBUILD_LIBWASM=ON -DWABT_INSTALL_RULES=OFF -DUSE_INTERNAL_SHA256=ON
cmake --build build/tests -j"$MAYHEM_JOBS"
