#!/usr/bin/env bats
# ↳ eMudhra/emSign intermediate CA compromise (INFIAAS-11916): no CA store in
#   the image may still trust the eight compromised intermediates.
#
# What "an intermediate fails verification" means here
# -----------------------------------------------------
# The intermediates (fixtures/emudhra-compromised/*.crt, 8 keys x 2 issuers)
# are issued by "emSign Root TLS/CS CA - G3" or cross-signed by Sectigo's
# "AAA Certificate Services". Neither G3 root is in Mozilla-derived stores, and
# Mozilla removed AAA years ago. The trust these stores granted came through a
# *cross-signature* of the G3 roots by "emSign ECC Root CA - G3", which a server
# using these intermediates sends in its chain. Verifying an intermediate on its
# own against a vulnerable store therefore fails too (no issuer), so a
# "supply no intermediates" test would pass on v4.9.5 and prove nothing.
# The checks are built so that they cannot pass vacuously:
#
#   * -untrusted gets the two published cross-signatures (fixtures/.../
#     cross-signs), and nothing else. That is the chain an attacker serves.
#     Untrusted certificates can never be trust anchors.
#   * -no-CAfile -no-CApath -no-CAstore, then exactly one explicit store.
#     Given only -CAfile, `openssl verify` still loads the default CApath, so a
#     certifi bundle would be "tested" with the system store mixed in.
#   * No -partial_chain: a non-self-signed certificate inside a bundle is not
#     accepted as an anchor.
#   * A rejection only counts as "error 20 ... unable to get local issuer
#     certificate", meaning no trust anchor. Any other failure, such as an
#     unreadable bundle or a broken fixture, is a test failure, not a pass.
#   * Bundles in TRUSTED CERTIFICATE (aux-trust) format, here only RHEL's
#     ca-bundle.trust.crt, cannot be judged with an intermediate as the target.
#     The purposes that read the trust bits (sslserver, codesign, ...) reject
#     a CA certificate at depth 0, `any` fails with error 28 even on a
#     vulnerable store, and the compat purposes (crlsign, ...) ignore the trust
#     bits altogether, so they would also accept a distrusted root. All of this
#     was measured on v4.9.5. That file is p11-kit's rendering of the trust
#     database that is extracted per purpose into tls-, email- and
#     objsign-ca-bundle.pem, which are checked instead.
#   * A positive control verifies every fixture OK against its real roots, so
#     a store that still carries either cross-signer root is guaranteed to fail
#     here (the v4.9.5 negative control is recorded under INFIAAS-11916
#     evidence/2026-10-26-ca-distrust-negative-control-4.9.5).
#
# The floors are hard-coded on purpose. They are the first releases with the
# distrust, not image pins. This suite is the guard, so it must not inherit a
# lowered value from the ENV of the image it checks. It is cherry-picked
# unchanged to release/4.8.

load 'test_helper/common.bash'

# bats file_tags=security,ca

PIP_FLOOR=26.2.2
UV_FLOOR=0.13.5
CERTIFI_FLOOR=2026.10.19

FIXTURES="$BATS_TEST_DIRNAME/fixtures/emudhra-compromised"

# Vendor-bundled stores that we neither build nor can patch in place. Per
# PRD Q2 the release ships with them documented as residuals (CHANGELOG and
# INFIAAS-11916 evidence/2026-10-26-vendor-ca-inventory-4.9.6/inventory.md).
# Format: "<shell glob>|<why / vendor tracking link>". Every run reports them
# on fd 3, and reports any that the vendor has fixed so the entry can go.
CA_RESIDUALS=(
)

setup_file() {
    # One file holding both cross-signatures, for -untrusted.
    cat "$FIXTURES"/cross-signs/*.crt >"$BATS_FILE_TMPDIR/untrusted.crt"
    export UNTRUSTED="$BATS_FILE_TMPDIR/untrusted.crt"
    # Content needles for discovering CA files: PEM line 8 of each cross-signer
    # root. Both lines fall inside the subjectPublicKeyInfo, so they are tied
    # to the key and are the same in every 64-column PEM bundle that carries
    # the root.
    NEEDLE_EMSIGN="$(sed -n 8p "$FIXTURES/roots/emsign-ecc-root-ca-g3.crt")"
    NEEDLE_AAA="$(sed -n 8p "$FIXTURES/roots/aaa-certificate-services.crt")"
    export NEEDLE_EMSIGN NEEDLE_AAA
}

# version_ge HAVE WANT: true when HAVE >= WANT (sort -V); false for an empty HAVE.
version_ge() {
    [ -n "$1" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" = "$2" ]
}

# _verify STORE CERT, where STORE is "-CAfile <file>", "-CApath <dir>" or
# "default" (OpenSSL's own default file and path, which curl and openssl use).
_verify() {
    if [ "$1" = default ]; then
        openssl verify -untrusted "$UNTRUSTED" "$2" 2>&1
    else
        openssl verify -no-CAfile -no-CApath -no-CAstore "$1" "$2" -untrusted "$UNTRUSTED" "$3" 2>&1
    fi
}

# assert_store_distrusts STORE: each of the 16 fixtures must be rejected with
# error 20 (see the header). Lists every offender on stderr.
assert_store_distrusts() {
    local store=("$@") cert out rc bad=()
    case "${store[0]}" in
        -CAfile) [ -s "${store[1]}" ] || { echo "CA bundle missing or empty: ${store[1]}" >&2; return 1; } ;;
        -CApath) [ -d "${store[1]}" ] || { echo "CA directory missing: ${store[1]}" >&2; return 1; } ;;
    esac
    for cert in "$FIXTURES"/*.crt; do
        out="$(_verify "${store[@]}" "$cert")" && rc=0 || rc=$?
        if [ "$rc" -eq 0 ]; then
            bad+=("  TRUSTED: $(basename "$cert")")
        elif ! grep -Eq '^error 20 at [0-9]+ depth lookup' <<<"$out"; then
            bad+=("  rejected for the wrong reason: $(basename "$cert"): ${out//$'\n'/ | }")
        fi
    done
    if [ "${#bad[@]}" -ne 0 ]; then
        printf '%s\n' "store ${store[*]} still trusts compromised intermediates:" "${bad[@]}" >&2
        return 1
    fi
}

# _find_ca_files DIR: NUL-separated text files under DIR that look like CA
# stores by name and contain a cross-signer root. Same filesystem only. This
# suite's own fixtures and bats' scratch space (the other tests' temporary
# venvs and anchor files) are pruned.
_find_ca_files() {
    find "$1" -xdev \( -path /proc -o -path /sys -o -path "$BATS_TEST_DIRNAME" \
        -o -path "${BATS_RUN_TMPDIR:-/nonexistent}" \) -prune -o \
        -type f \( -name '*.pem' -o -name '*.crt' -o -name '*.cer' -o -name 'cacert*' -o -name '*bundle*.txt' \) \
        -print0 2>/dev/null |
        xargs -0 -r grep -lIZF -e "$NEEDLE_EMSIGN" -e "$NEEDLE_AAA" 2>/dev/null || true
}

# _residual_reason FILE: print the CA_RESIDUALS reason when FILE matches an entry.
_residual_reason() {
    local entry glob
    for entry in "${CA_RESIDUALS[@]}"; do
        glob="${entry%%|*}"
        # shellcheck disable=SC2053  # the glob is meant to match
        [[ "$1" == $glob ]] && { echo "${entry#*|}"; return 0; }
    done
    return 1
}

# Print the pip version of interpreter $1 ("" if it has no pip).
_pip_version() { "$1" -m pip --version 2>/dev/null | awk '{print $2}'; }

# Print the vendored certifi bundle of interpreter $1's pip.
_pip_certifi() { "$1" -c 'from pip._vendor import certifi; print(certifi.where())'; }

# Interpreters whose pip this image installs: every pyenv CPython and the
# OpenStack venv. Vendor interpreters (az, gcloud) fall to the discovery test.
_owned_pythons() {
    ls -d /opt/pyenv/versions/*/bin/python
    echo /opt/openstack/bin/python
}

# ----------------------------------------------------------------------------
# Fixture integrity and positive control
# ----------------------------------------------------------------------------

@test "fixtures: 16 certificates = 8 compromised intermediate keys x 2 issuers" {
    local certs=("$FIXTURES"/*.crt)
    [ "${#certs[@]}" -eq 16 ] || fail "expected 16 intermediate certificates, found ${#certs[@]}"
    run bash -c 'for c in "$@"; do openssl x509 -in "$c" -noout -pubkey | openssl sha256; done | sort -u | wc -l' _ "${certs[@]}"
    assert_success
    assert_output "8"
}

@test "fixtures: every certificate matches its SHA-256 in README.md, and README lists no extra file" {
    local readme="$FIXTURES/README.md" f want have listed=0 bad=()
    while IFS= read -r f; do
        want="$(sed -nE "s#^\| \`${f//./\\.}\` \|.*\| \`([0-9A-F]{64})\` \|\$#\1#p" "$readme")"
        have="$(openssl x509 -in "$FIXTURES/$f" -noout -fingerprint -sha256 | sed 's/.*=//; s/://g')"
        [ -n "$want" ] && [ "$want" = "$have" ] || bad+=("$f: README=${want:-<missing>} actual=$have")
    done < <(cd "$FIXTURES" && find . -name '*.crt' -printf '%P\n' | sort)
    listed="$(grep -cE '^\| `[^`]+\.crt` \|.*\| `[0-9A-F]{64}` \|$' "$readme")"
    [ "${#bad[@]}" -eq 0 ] || fail "$(printf '%s\n' "${bad[@]}")"
    [ "$listed" -eq "$(find "$FIXTURES" -name '*.crt' | wc -l)" ] || fail "README lists $listed certificates"
}

@test "positive control: every fixture verifies OK against the cross-signer roots (the suite can go red)" {
    # Anchors are only the two cross-signer roots, not the G3 roots, so the
    # emSign-issued fixtures must take the cross-signature path that the
    # vulnerable stores trusted.
    cat "$FIXTURES/roots/emsign-ecc-root-ca-g3.crt" "$FIXTURES/roots/aaa-certificate-services.crt" \
        >"$BATS_TEST_TMPDIR/anchors.crt"
    local cert bad=()
    for cert in "$FIXTURES"/*.crt; do
        _verify -CAfile "$BATS_TEST_TMPDIR/anchors.crt" "$cert" >/dev/null || bad+=("$(basename "$cert")")
    done
    [ "${#bad[@]}" -eq 0 ] || fail "fixtures not verifiable against their own roots: ${bad[*]}"
}

@test "positive control: CA-file discovery finds a bundle that carries a cross-signer root" {
    [ "${#NEEDLE_EMSIGN}" -eq 64 ] && [ "${#NEEDLE_AAA}" -eq 64 ] || fail "needles must be full 64-column PEM lines"
    local found
    found="$(_find_ca_files "$FIXTURES/roots" | tr '\0' '\n' | sort)"
    [ "$found" = "$(printf '%s\n' "$FIXTURES/roots/aaa-certificate-services.crt" "$FIXTURES/roots/emsign-ecc-root-ca-g3.crt")" ] \
        || fail "discovery found: ${found:-<nothing>}"
}

# ----------------------------------------------------------------------------
# Stores the image owns: these must be fixed, with no residual allowance
# ----------------------------------------------------------------------------

@test "system trust store distrusts: ca-bundle.crt, the TLS/email/objsign extractions, directory-hash, OpenSSL default" {
    local rc=0 extracted=/etc/pki/ca-trust/extracted/pem
    assert_store_distrusts -CAfile /etc/pki/tls/certs/ca-bundle.crt || rc=1
    assert_store_distrusts -CAfile "$extracted/tls-ca-bundle.pem" || rc=1
    assert_store_distrusts -CAfile "$extracted/email-ca-bundle.pem" || rc=1
    assert_store_distrusts -CAfile "$extracted/objsign-ca-bundle.pem" || rc=1
    assert_store_distrusts -CApath "$extracted/directory-hash" || rc=1
    assert_store_distrusts default || rc=1
    return "$rc"
}

@test "certifi in the tool venv (/tmp/.venv) is at the incident floor and distrusts" {
    run /tmp/.venv/bin/python -c 'import certifi; print(certifi.__version__); print(certifi.where())'
    assert_success
    version_ge "${lines[0]}" "$CERTIFI_FLOOR" || fail "certifi ${lines[0]} < ${CERTIFI_FLOOR}"
    assert_store_distrusts -CAfile "${lines[1]}"
}

@test "certifi in the OpenStack venv (/opt/openstack) is at the incident floor and distrusts" {
    run /opt/openstack/bin/python -c 'import certifi; print(certifi.__version__); print(certifi.where())'
    assert_success
    version_ge "${lines[0]}" "$CERTIFI_FLOOR" || fail "certifi ${lines[0]} < ${CERTIFI_FLOOR}"
    assert_store_distrusts -CAfile "${lines[1]}"
}

@test "every pip the image installs (pyenv CPython, /opt/openstack) is at the floor and its vendored certifi distrusts" {
    # pip always loads its vendored certifi in addition to the system store,
    # whatever `pip config global.cert` says, so OS fixes do not cover it.
    local py v rc=0 n=0
    while IFS= read -r py; do
        n=$((n + 1))
        v="$(_pip_version "$py")"
        version_ge "$v" "$PIP_FLOOR" || { echo "$py: pip ${v:-<none>} < ${PIP_FLOOR}" >&2; rc=1; continue; }
        assert_store_distrusts -CAfile "$(_pip_certifi "$py")" || rc=1
    done < <(_owned_pythons)
    [ "$n" -ge 2 ] || fail "expected at least the pyenv and OpenStack interpreters, found $n"
    return "$rc"
}

@test "pipenv's patched pip is at the floor and its vendored certifi distrusts" {
    run /tmp/.venv/bin/python -c 'import os, pipenv; print(os.path.dirname(pipenv.__file__))'
    assert_success
    local pip_dir="$output/patched/pip" v
    v="$(sed -nE 's/^__version__ = "([^"]+)"/\1/p' "$pip_dir/__init__.py")"
    version_ge "$v" "$PIP_FLOOR" || fail "pipenv's patched pip is ${v:-<unknown>} < ${PIP_FLOOR}"
    assert_store_distrusts -CAfile "$pip_dir/_vendor/certifi/cacert.pem"
}

@test "new venvs get a fixed pip: python -m venv (ensurepip) and virtualenv (embedded seed wheel)" {
    # Offline by construction: ensurepip and virtualenv --no-download both
    # install the pip wheel that ships inside the image.
    local py v rc=0
    py="$(_owned_pythons | head -n1)"
    "$py" -m venv "$BATS_TEST_TMPDIR/stdlib"
    VIRTUALENV_OVERRIDE_APP_DATA="$BATS_TEST_TMPDIR/vapp" \
        /tmp/.venv/bin/virtualenv --no-download --no-periodic-update -q -p "$py" "$BATS_TEST_TMPDIR/virtualenv"
    local kind
    for kind in stdlib virtualenv; do
        v="$(_pip_version "$BATS_TEST_TMPDIR/$kind/bin/python")"
        version_ge "$v" "$PIP_FLOOR" || { echo "$kind venv seeds pip ${v:-<none>} < ${PIP_FLOOR}" >&2; rc=1; continue; }
        assert_store_distrusts -CAfile "$(_pip_certifi "$BATS_TEST_TMPDIR/$kind/bin/python")" || rc=1
    done
    return "$rc"
}

@test "uv: every uv binary (PATH and ~/.local/bin) is at the floor (embedded root store)" {
    [ -x "$HOME/.local/bin/uv" ] || fail "~/.local/bin/uv is missing"
    local u v bad=()
    while IFS= read -r u; do
        v="$("$u" --version | awk '{print $2}')"
        version_ge "$v" "$UV_FLOOR" || bad+=("$u: ${v:-<none>}")
    done < <({ type -ap uv; echo "$HOME/.local/bin/uv"; } | xargs -r realpath | sort -u)
    [ "${#bad[@]}" -eq 0 ] || fail "uv older than ${UV_FLOOR}: ${bad[*]}"
}

@test "node: the built-in root store (tls.rootCertificates) holds no emSign/AAA root" {
    # Matched by SHA-256 against fixtures/roots and, as the plan asks, by the
    # cross-signer's subject CN, in case it is ever re-issued.
    run node -e '
        const { X509Certificate } = require("crypto");
        const fs = require("fs"), path = require("path"), tls = require("tls");
        const dir = process.argv[1];
        const banned = new Set(fs.readdirSync(dir).map(f =>
            new X509Certificate(fs.readFileSync(path.join(dir, f))).fingerprint256));
        const roots = tls.rootCertificates.map(p => new X509Certificate(p));
        if (roots.length < 100) { console.log(`only ${roots.length} roots: store not loaded?`); process.exit(2); }
        const hits = roots.filter(c => banned.has(c.fingerprint256) || /^CN=emSign ECC Root CA - G3$/m.test(c.subject));
        hits.forEach(c => console.log("in tls.rootCertificates:", c.subject.replace(/\n/g, ", ")));
        process.exit(hits.length ? 1 : 0);
    ' "$FIXTURES/roots"
    assert_success
}

# ----------------------------------------------------------------------------
# Everything else on disk (vendor CLIs and their bundled Pythons)
# ----------------------------------------------------------------------------

@test "every PEM CA file on disk that carries a cross-signer root distrusts (documented residuals excepted)" {
    local f reason failed=()
    while IFS= read -r -d '' f; do
        if grep -q -- '-----BEGIN TRUSTED CERTIFICATE-----' "$f"; then
            echo "# aux-trust bundle, judged through its per-purpose extractions (see header): $f" >&3
            continue
        fi
        if reason="$(_residual_reason "$f")"; then
            if assert_store_distrusts -CAfile "$f" 2>/dev/null; then
                echo "# residual now fixed, drop it from CA_RESIDUALS: $f" >&3
            else
                echo "# residual ($reason): $f" >&3
            fi
            continue
        fi
        assert_store_distrusts -CAfile "$f" || failed+=("$f")
    done < <(_find_ca_files /)
    [ "${#failed[@]}" -eq 0 ] || fail "$(printf '%s\n' "CA files that still trust compromised intermediates:" "${failed[@]}")"
}
