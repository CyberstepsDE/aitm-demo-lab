# AiTM Demo Lab — build log

Chronological record of how this was built and tested (2026-10-29 to 2026-10-31). Clean instructions
are in `README.md`; this is the "why", the dead ends, and what to do if it breaks again.

## 1. Tenant recon (read-only, via Graph, 2026-10-29)

Checked `GET /identity/conditionalAccess/policies` against the cybersteps tenant
(`c0531484-50fa-4ff2-97df-b1f2d4810603`): every CA policy in the tenant is
`enabledForReportingButNotEnforced` or `disabled` — **none enforce anything**, including the
"Require multifactor authentication for all users" policy. Security Defaults check 403'd (missing
Graph scope on the CLI token), but given CA policies are configured at all, Security Defaults is
almost certainly off too.

**Practical effect:** enrolling an MFA method on a user does *not* make Entra challenge for it —
nothing in the tenant currently requires MFA for anyone. Confirmed directly: after enrolling the
demo account's Authenticator method, a login with just the password went straight through with no
MFA screen at all.

**Fix used:** per-user MFA (legacy), turned on for only the one demo account at
https://account.activedirectory.windowsazure.com/UserManagement/MultifactorVerification.aspx. This
is a tenant security-setting change — not something an AI session can do; Roman did it himself. If
it's ever found disabled again (nobody should be touching it, but), that page is where to re-enable
it. A scoped Conditional Access policy (user = only the demo account, grant = require MFA, state =
On) would work equally well if that legacy page is ever retired.

No spare paid license in the tenant (`M365EDU_A5_FACULTY` and `STANDARDWOFFPACK_FACULTY` both fully
consumed) — doesn't matter, the demo only needs to reach the Entra sign-in page, not a mailbox.

## 2. The demo account

`training-demo-donotuse@cybersteps.onmicrosoft.com` — zero roles, zero group memberships, no
license. Created via:

```bash
az ad user create --display-name "Training Demo (do not use)" \
  --user-principal-name training-demo-donotuse@cybersteps.onmicrosoft.com \
  --password '<password>' --force-change-password-next-sign-in true
```

Gotcha: Entra's banned-password list blocks any password containing the org name
("Cybersteps") — pick something else, or `az ad user create` fails with
`Property passwordProfile.password has an invalid value`.

MFA enrolled manually (Security info page → Add method → Authenticator app → "I want to use a
different authenticator app" → "Can't scan the image?" → copy the base32 secret) instead of scanning
a QR code, specifically so the TOTP secret is a plain string any instructor can use — no phone or
registered device needed. See §4 for why that works and §1 for why MFA has to be force-enabled
separately.

**Why an AI session can't do any of this itself:** account creation, setting a password, and
enrolling MFA are all things Claude is hard-blocked from doing even when explicitly asked — doesn't
matter whose tenant or how low-privilege the account. Had to hand Roman exact commands/portal steps
and wait. If this account ever needs recreating (new cohort, compromised secret, whatever), the same
applies — a session can prep the exact commands but a human has to run the account-creation and MFA
steps.

## 3. Evilginx2 — install and build

All of §3-5 below was built and verified end-to-end on macOS first (Apple Silicon, `brew install go`
got 1.27.3), then the lab was repointed at Kali Linux for actual classroom use (README.md targets
Kali; `scripts/setup.sh` uses `apt`) since that matches the VM students already use for RECON 9 Ex 3.
Nothing in evilginx2 itself or the phishlet is OS-specific — same binary build process either way
(`git clone` + `make`), same `/etc/hosts` trick. One Kali-only wrinkle: `systemd-resolved` usually
already holds port 53, so evilginx2's own DNS server fails to bind and logs a `[fatal]`-labeled line
at startup — harmless, since this demo never uses evilginx2's DNS server (`/etc/hosts` does the
resolving). Don't stop `systemd-resolved` to silence it.

Cloned `https://github.com/kgretzky/evilginx2` (current release 3.3.0 as of this writing) and
`make`'d it — builds clean, no changes needed to the tool itself. `-developer` flag still exists and
does what the old docs say (self-signed certs, skip Let's Encrypt).

## 4. TOTP-without-a-device — validated

`brew install oath-toolkit`, then:

```bash
oathtool --totp -b <secret>
```

run twice (simulating two different instructors) at the same moment produces the identical 6-digit
code both times — confirms TOTP is pure `HMAC(secret, time_window)` math, nothing device-bound. Any
machine with the secret and a roughly-synced clock produces the same code Microsoft Authenticator
would. This is why the secret can live in a shared instructor doc instead of needing a registered
device per instructor.

## 5. The phishlet — two real bugs found and fixed

Started from `https://github.com/ArchonLabs/evilginx2/tree/master/phishlets` (`o365.yaml`,
`min_ver: 2.3.0`) since Evilginx2's Community Edition ships no phishlets of its own anymore (bundled
ones are a Pro-only feature now; `phishlets/example.yaml` is just a documentation template). Checked
two more actively-maintained public phishlet collections before patching this one further
(An0nUD4Y's repo has been taken down by GitHub; `simplerhacking/evilginx3-phishlets` exists but its
Microsoft phishlets target either personal `live.com` accounts or assume ADFS federation — neither
matches a plain cloud-only Entra tenant like ours) — decided patching the known-working one was lower
risk than switching to an unknown one, since credential capture with it was already proven reliable.

**Bug 1 — missing proxy host.** Modern Entra sign-in now does a step via
`device.login.microsoftonline.com` (looked like a device-bound/passkey probe) partway through login.
The old phishlet never accounted for it, so that step hit a bare `/etc/hosts` miss
(`DNS_PROBE_FINISHED_NXDOMAIN`) and killed the whole login flow. Fixed by adding one more
`proxy_hosts` entry and the matching `/etc/hosts` line:

```yaml
- {phish_sub: 'device.login', orig_sub: 'device.login', domain: 'microsoftonline.com', session: false, is_landing:false}
```

**Bug 2 — session never marked "captured" despite the right cookies being intercepted.** The
phishlet's `auth_tokens` section had two separate domain blocks:

```yaml
auth_tokens:
  - domain: '.login.microsoftonline.com'      # leading dot
    keys: ['ESTSAUTH', 'ESTSAUTHPERSISTENT']
  - domain: 'login.microsoftonline.com'        # NO leading dot — bug
    keys: ['SignInStateCookie']
```

Evilginx2 always normalizes a captured cookie's domain with a leading dot internally
(`core/http_proxy.go`, around line 990) before storing it — so a requirement registered under a
no-dot domain key can *never* be satisfied, even though the cookie itself is being captured
correctly (confirmed with `-debug`: the log clearly showed `session: .login.microsoftonline.com:
SignInStateCookie = ...` being captured, but `sessions` still listed `tokens: none`). Fix: dropped
the `SignInStateCookie` requirement entirely — `ESTSAUTH` + `ESTSAUTHPERSISTENT` are the actual
session-auth cookies and are sufficient on their own; fewer required keys is also more robust if
Microsoft tweaks cookie names again later.

Confirmed fixed end-to-end 2026-10-31: full login + real MFA challenge + code verified +
`sessions` → `tokens: captured` → exported cookie JSON (`sessions <id>`) is well-formed and
importable via the StorageAce browser extension.

## 6. If Microsoft changes the login flow again

This will probably need occasional re-patching — Microsoft's sign-in experience changes more often
than public Evilginx2 phishlets get updated. The debugging method that worked, in order:

1. Run evilginx2 with `-debug` added.
2. Do a full login attempt through the lure.
3. `grep` the console output for `session: <domain>: <cookie> = ...` lines — that's the exact set of
   cookies evilginx2 is capturing, regardless of whether `phishlets/o365.yaml` currently asks for
   them.
4. Compare to the `auth_tokens` section — fix domain formatting (always `.`-prefixed) or key names
   to match.
5. If a step in the flow hits a dead host (NXDOMAIN or `ERR_TIMED_OUT` partway through, not at the
   very start), run `phishlets get-hosts o365` and diff against `/etc/hosts` — add whatever's new to
   both the phishlet's `proxy_hosts` and `/etc/hosts`.
6. **Full restart required after any phishlet YAML edit** — `phishlets disable`/`enable` only
   toggles state, it does not re-read the file from disk. This cost real debugging time, don't
   assume `disable`/`enable` applied an edit.
