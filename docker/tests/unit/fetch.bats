#!/usr/bin/env bats
# Unit tests for docker/files/bin/fetch.
#
# fetch `exec`s `curl` BY BARE NAME, so we shim curl on PATH (in tmpdir) with a
# recorder and test the REAL fetch directly. We deliberately do NOT put the
# fetch fixture-shim on PATH here — this suite is about fetch itself.

setup() {
  BIN="$BATS_TEST_DIRNAME/../../files/bin"
  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  # Recorder curl: dump argv (one per line) and exit with $CURL_RC (default 0).
  cat > "$STUB/curl" <<'CURL'
#!/usr/bin/env bash
: "${CURL_RC:=0}"
printf '%s\n' "$@" > "$CURL_LOG"
exit "$CURL_RC"
CURL
  chmod +x "$STUB/curl"
  export CURL_LOG="$BATS_TEST_TMPDIR/curl.args"
  # curl stub first, then the real helper dir; NO fixtures/bin fetch shim.
  PATH="$STUB:$BIN:$PATH"
  export PATH
}

# Real fetch: host -> $BIN/fetch; helpers stage -> /usr/local/bin/fetch (PATH).
FETCH() { if [ -x "$BIN/fetch" ]; then "$BIN/fetch" "$@"; else command fetch "$@"; fi; }

@test "fetch passes user args through to curl unchanged (order preserved)" {
  run FETCH -o /tmp/out https://example.test/artifact
  [ "$status" -eq 0 ]
  # last three recorded args must be exactly our args, in order
  tail -3 "$CURL_LOG" | tr '\n' '|'
  [ "$(tail -3 "$CURL_LOG" | tr '\n' '|')" = "-o|/tmp/out|https://example.test/artifact|" ]
}

@test "fetch propagates curl's exit code (via exec)" {
  CURL_RC=22 run FETCH https://example.test/missing
  [ "$status" -eq 22 ]
}

@test "fetch applies the four FETCH_* defaults when unset" {
  run FETCH https://example.test/x
  [ "$status" -eq 0 ]
  grep -qx -- '--retry' "$CURL_LOG"
  # value follows its flag; assert each default pair is present in order
  awk 'p=="--retry"{print "retry="$0} p=="--retry-delay"{print "delay="$0} p=="--connect-timeout"{print "ct="$0} p=="--max-time"{print "mt="$0} {p=$0}' "$CURL_LOG" > "$BATS_TEST_TMPDIR/pairs"
  grep -qx 'retry=5' "$BATS_TEST_TMPDIR/pairs"
  grep -qx 'delay=2' "$BATS_TEST_TMPDIR/pairs"
  grep -qx 'ct=20' "$BATS_TEST_TMPDIR/pairs"
  grep -qx 'mt=900' "$BATS_TEST_TMPDIR/pairs"
}

@test "fetch honours FETCH_* overrides from the environment" {
  FETCH_RETRIES=9 FETCH_MAX_TIME=1 run FETCH https://example.test/x
  [ "$status" -eq 0 ]
  awk 'p=="--retry"{print "retry="$0} p=="--max-time"{print "mt="$0} {p=$0}' "$CURL_LOG" > "$BATS_TEST_TMPDIR/pairs"
  grep -qx 'retry=9' "$BATS_TEST_TMPDIR/pairs"
  grep -qx 'mt=1' "$BATS_TEST_TMPDIR/pairs"
}
