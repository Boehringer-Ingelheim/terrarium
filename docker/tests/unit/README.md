# Unit tests for `docker/files/bin/` helpers

These tests cover the extracted helper scripts **without building the image**
and **without network access**. They run in two places, identically:

- **Host:** `make test-helpers` (needs only `bats` on PATH).
- **Image:** `make docker-test-helpers` builds the `helpers` stage, which runs
  `bats /opt/unit`. CI runs this stage before the main build.

## Hermeticity rule (enforced by review and by the tests)

A unit test here MUST:

1. Use **bats core only** — no `bats-support`, no `bats-assert`. (The
   image-level suite in `docker/tests/*.bats` keeps using bats-assert; this tier
   deliberately does not, so it runs on a bare checkout with nothing vendored.)
2. Make **no network calls.** Helpers that download go through the `fetch` shim
   in [`fixtures/bin/fetch`](fixtures/bin/fetch), which serves bytes from a
   fixture map and **fails on any unmapped URL** — that failure is what proves a
   test never reached the network.
3. Touch **nothing outside `$BATS_TEST_TMPDIR`** — not the image filesystem, not
   `$HOME`, not `/opt`, not `/usr/local`.

## How a helper is located

`setup()` prepends both the fixture shim dir and the real helper dir to `PATH`:

```bash
BIN="$BATS_TEST_DIRNAME/../../files/bin"          # host: docker/files/bin
PATH="$BATS_TEST_DIRNAME/fixtures/bin:$BIN:$PATH" # shim wins over real fetch
```

On the host, helpers resolve via `$BIN`. In the `helpers` stage they are copied
to `/usr/local/bin` (already on PATH), so the same tests pass unchanged. Use
`helper_path <name>` (defined per-suite) when a test needs the file itself
(e.g. to grep its contents) rather than to execute it.

## The `fetch` shim contract

`fetch [-H hdr]... [-o outpath] <URL>` — mirrors the real helper's surface.
It resolves `<URL>` against `$FIXTURE_MAP` (a file of `URL<TAB>relative-path`
lines under `$FIXTURE_DIR`) or, if unset, against `$FIXTURE_DIR/<basename>`.
Unmapped URL → exit 1. Missing `-o` → writes to stdout.
