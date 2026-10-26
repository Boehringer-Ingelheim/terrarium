# eMudhra/emSign compromised intermediates (INFIAAS-11916)

Fixtures for [`../../15_ca_distrust.bats`](../../15_ca_distrust.bats). They are
**public CA certificates only**, with no private keys. They are named `*.crt`
(PEM-encoded) rather than `*.pem` so that secret-file guards which key on the
`.pem` extension do not flag them.

## What happened

The private keys of **eight eMudhra intermediate CAs** can be recovered from
their public certificates. Each intermediate exists twice: issued by an emSign
G3 root, and cross-signed by Sectigo's *AAA Certificate Services*. The 16
certificates are therefore 8 intermediates × 2 issuers. The suite asserts the
"8 distinct keys" count.

The emSign G3 roots (*emSign Root TLS CA - G3*, *emSign Root CS CA - G3*) are
not in the Mozilla store themselves. Mozilla-derived stores trusted the
intermediates **through a cross-signature by *emSign ECC Root CA - G3***, which
is Mozilla-included. A server using one of these intermediates sends that
cross-signature in its chain (see the incident site's `chains.zip`). The fixed
stores (certifi 2026.10.19+, pip 26.2.2, Node 24.22.1, RHEL `ca-certificates`
2026.2.92) remove *emSign ECC Root CA - G3*.

## Layout

| Path | Contents | Used for |
| --- | --- | --- |
| `*.crt` | the 16 compromised intermediate certificates | every store must reject each one |
| `cross-signs/*.crt` | *emSign Root TLS/CS CA - G3* cross-signed by *emSign ECC Root CA - G3* | passed as `-untrusted`, i.e. the chain an attacker would serve |
| `roots/*.crt` | the four issuing and cross-signing roots | the positive control (proves that the suite can go red), the Node root-store check, and the content needles for discovering CA files |

## Sources (fetched 2026-10-26, treated as data)

- Intermediates: <https://emudhra.we-have-a-problem.com/impacted-intermediates.json>.
  Each entry's PEM was decoded and its SHA-256 recomputed against the JSON's own
  `sha256` field.
- Roots: <https://emudhra.we-have-a-problem.com/roots.json>, checked the same way.
- Cross-signs: crt.sh [14658191778](https://crt.sh/?id=14658191778) (TLS) and
  [14658191774](https://crt.sh/?id=14658191774) (CS). The TLS cross-sign is
  byte-identical to the third certificate of every non-AAA chain in the incident
  site's `chains.zip`.
- Context: [Mozilla bug 2083449](https://bugzilla.mozilla.org/show_bug.cgi?id=2083449),
  [incident site](https://emudhra.we-have-a-problem.com/).

## SHA-256 fingerprints (DER)

`15_ca_distrust.bats` parses this table and fails if a fixture is missing,
unlisted, or does not match. Keep the format: `` | `path` | subject ← issuer | `SHA256` | ``.

| File | Subject ← issuer | SHA-256 |
| --- | --- | --- |
| `em-dv-tls-ca-g3b--emsign.crt` | EM DV TLS CA - G3B ← emSign Root TLS CA - G3 | `42C4ACCD12C4F59597925E1A08A7A90102608543809308D50EC427E118BA1493` |
| `em-dv-tls-ca-g3b--sectigo-aaa.crt` | EM DV TLS CA - G3B ← AAA Certificate Services | `45A883F349AEDFD5F3A649B5498FFB121712BA8B448F3F2A91DBC5A766FCDDBE` |
| `em-dv-tls-ca-g3c--emsign.crt` | EM DV TLS CA - G3C ← emSign Root TLS CA - G3 | `0164D7CEAE5BB909C272AF151FF44B1177AE9B47D9424B94F1D9558C30934D19` |
| `em-dv-tls-ca-g3c--sectigo-aaa.crt` | EM DV TLS CA - G3C ← AAA Certificate Services | `62B7F9868263F72F6911FC78CEAF72C1979158B7368BF648683BB2AA39B02E72` |
| `em-ev-tls-ca-g3b--emsign.crt` | EM EV TLS CA - G3B ← emSign Root TLS CA - G3 | `E7568FE6E12331F4FD7DE61DA4C7559D0F8EB192A218D4741A3BA75184333838` |
| `em-ev-tls-ca-g3b--sectigo-aaa.crt` | EM EV TLS CA - G3B ← AAA Certificate Services | `579480AEA166290BD3C643589E795FC0D0E54E86505D180F1DFF99EFD3199512` |
| `em-ev-tls-ca-g3c--emsign.crt` | EM EV TLS CA - G3C ← emSign Root TLS CA - G3 | `432EC25F0D28DE9006D97BF752F17BBB2CD41F669933FCB072D9A1148D0261F3` |
| `em-ev-tls-ca-g3c--sectigo-aaa.crt` | EM EV TLS CA - G3C ← AAA Certificate Services | `FD9D5C2DBBD4995AB69B8D50C439D9527B00529199C2FD01B2174EB58F07021F` |
| `em-ov-cs-ca-g3b--emsign.crt` | EM OV CS CA - G3B ← emSign Root CS CA - G3 | `9E39DE2881273ACC225A149C72BA3E0F51424963669AB633EE1DC7DF5DB067B4` |
| `em-ov-cs-ca-g3b--sectigo-aaa.crt` | EM OV CS CA - G3B ← AAA Certificate Services | `A496E23AC0CAB8155FC9B117B97EAE368EFCBB9041AEC8804D5A308D2D01C2D8` |
| `em-ov-cs-ca-g3c--emsign.crt` | EM OV CS CA - G3C ← emSign Root CS CA - G3 | `4B2460A466F95FD40113BCDCCA2CEB29B3B093921DE45474DA7DF48874C630B1` |
| `em-ov-cs-ca-g3c--sectigo-aaa.crt` | EM OV CS CA - G3C ← AAA Certificate Services | `84112972B8E59D14560AE7E7119654474AAD119990CF3722BFC1E3B91615E1FD` |
| `em-ov-tls-ca-g3b--emsign.crt` | EM OV TLS CA - G3B ← emSign Root TLS CA - G3 | `98B896625C0C230ADEEC3EB2CF6AAD5001ECF9156A68644E82374CE5833BC25B` |
| `em-ov-tls-ca-g3b--sectigo-aaa.crt` | EM OV TLS CA - G3B ← AAA Certificate Services | `5F1DED4DD590AF74631290CF073B122A2AAC6A1FA479778A0BD43579BD832699` |
| `em-ov-tls-ca-g3c--emsign.crt` | EM OV TLS CA - G3C ← emSign Root TLS CA - G3 | `CB6E15165AC802E9B3F993F16C25D41F4E81C21EBDE71AE1B012AC00BF9C7C3F` |
| `em-ov-tls-ca-g3c--sectigo-aaa.crt` | EM OV TLS CA - G3C ← AAA Certificate Services | `7485B51C0ED192878FA1D2F948FB529AE1842CC5086C4B67F7BE5B2039DE9489` |
| `cross-signs/emsign-root-cs-ca-g3--by-emsign-ecc-root-ca-g3.crt` | emSign Root CS CA - G3 ← emSign ECC Root CA - G3 | `7137FA71AD46BA686F746D1014AC57E8E6C6E9AF4AA2F73C0C44A5CF27DEBB59` |
| `cross-signs/emsign-root-tls-ca-g3--by-emsign-ecc-root-ca-g3.crt` | emSign Root TLS CA - G3 ← emSign ECC Root CA - G3 | `3094025792039A68AF6E553686410BDAB7C0D4A36B9084CBA64202E35D6EBBDD` |
| `roots/aaa-certificate-services.crt` | AAA Certificate Services ← AAA Certificate Services | `D7A7A0FB5D7E2731D771E9484EBCDEF71D5F0C3E0A2948782BC83EE0EA699EF4` |
| `roots/emsign-ecc-root-ca-g3.crt` | emSign ECC Root CA - G3 ← emSign ECC Root CA - G3 | `86A1ECBA089C4A8D3BBE2734C612BA341D813E043CF9E8A862CD5C57A36BBE6B` |
| `roots/emsign-root-cs-ca-g3.crt` | emSign Root CS CA - G3 ← emSign Root CS CA - G3 | `F2EDAAFF3D9B701FB4D14C9F285F8C0BAD90FC3BCC1FA07D47F4718EDABA34A5` |
| `roots/emsign-root-tls-ca-g3.crt` | emSign Root TLS CA - G3 ← emSign Root TLS CA - G3 | `7DD78D5F4F13459A83DFF9ABBBA62EDBAF6F2D102BF257FD712F4D9F2746ED8D` |

## Refreshing

If the incident site publishes more intermediates, append them here and add the
`.crt`. Do not edit a certificate by hand: the fingerprint check catches
truncation, and the positive-control test catches a fixture that no longer
chains to its roots.
