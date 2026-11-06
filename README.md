# AiTM Phishing Demo Lab (Evilginx2) — instructor guide

A live, local demo for Module 2 Week 1 (social engineering / OSINT / phishing), Session 5: an
Adversary-in-the-Middle (AiTM) phishing attack against a throwaway Entra ID account in our own
tenant, showing that it steals a working session **even after MFA passes**. Same pattern as the
published LMS exercise "RECON 9 Ex 3: Ginxed It" (students run Evilginx2 locally against their own
account) — this is the instructor-facing version against a dedicated demo account instead.

**Runs in a Kali Linux VM** (the same kind of VM students already use for RECON 9 Ex 3, so the
environment is familiar). Nothing here touches student machines or the real Cybersteps domain —
it's a fake local domain (`cyberlogin-demo.test`) resolved only via `/etc/hosts` inside the Kali VM,
reverse-proxying to the real `login.microsoftonline.com`. A browser running on the Kali VM itself
(Firefox ESR, preinstalled) is what you demo from — no host-machine config needed.

Chronological build/debug log (every dead end, for whoever maintains this next): `ENVIRONMENT-SETUP.md`.

**This repo is public — it contains no secrets on purpose.** The demo account's password and TOTP
secret live in the Academic Instruction of the Module 2 session "SE 5 Bypassing MFA" in the LMS (staff only), not in this repo. If
you're an instructor running this and can't open it, ask Roman.

## 1. What this demonstrates

1. Student (played by the instructor) clicks a phishing link that looks like a Microsoft login page.
2. They type their real password into it. The attacker (Evilginx2, sitting in the middle) silently
   forwards everything to the real Microsoft login and relays the real response back — the victim
   sees a completely normal, working login flow.
3. Microsoft challenges for MFA. The victim enters a real, valid MFA code. It passes.
4. Microsoft issues a normal, legitimate session cookie to the victim's browser — but it passes
   *through* the attacker's proxy on the way, and the attacker keeps a copy.
5. The attacker now has a fully-authenticated session cookie, with MFA already satisfied, that can
   be loaded into a completely different browser with no further login — bypassing MFA entirely,
   because MFA was never broken, just captured *after* the real user did it.

The punchline for students: MFA stops credential stuffing, it does **not** stop phishing when the
phishing page is a live proxy, not a static clone.

## 2. One-time setup (before class)

Needs: a Kali Linux VM, sudo rights, internet access from the VM (to install packages and clone
Evilginx2 from GitHub). Clone or copy this repo into the VM first.

```bash
cd aitm-demo-lab
./scripts/setup.sh
```

This `apt install`s `golang-go`, `oathtool`, `git`, `make` if missing, clones + builds Evilginx2
from source into `vendor/evilginx2/build/evilginx` (gitignored — build artifact, not committed),
and adds three `/etc/hosts` entries (asks for your sudo password once).

**Port 53 note:** Kali's `systemd-resolved` usually already holds port 53. Evilginx2 tries to bind
its own DNS server there too at startup and will print a `[fatal]`-labeled line if that fails —
that's expected and harmless here: this demo resolves the fake domain via `/etc/hosts`, not
evilginx's own DNS server, so the HTTPS side (the actual demo) works fine regardless. Don't stop
`systemd-resolved` to "fix" this — it breaks the VM's normal DNS for no benefit.

**The demo account already exists** — don't recreate it. Get the UPN, password, and TOTP secret from
the Academic Instruction of the Module 2 session "SE 5 Bypassing MFA" in the LMS (staff only), not in this repo (see the note at the top). If you need a fresh
account for a new cohort, see "Rebuilding the demo account" in `ENVIRONMENT-SETUP.md` — it requires
a human (not an AI session) to actually create the Entra user and enroll MFA; that's deliberate, see
that doc for why.

## 3. Run the demo (do this live, in front of students)

**Terminal 1 — start Evilginx2** (needs sudo, since it binds ports 443/53):

```bash
sudo ./vendor/evilginx2/build/evilginx -developer -c ./run/config -p ./phishlets
```

`-developer` makes it generate a self-signed cert instead of trying to get a real one from Let's
Encrypt — expected for a local-only demo, causes the "connection not private" warning in step 4.

At the `:` prompt, type:

```
config domain cyberlogin-demo.test
config ipv4 external 127.0.0.1
phishlets hostname o365 cyberlogin-demo.test
phishlets enable o365
lures create o365
lures get-url 0
```

Copy the printed URL (looks like `https://login.cyberlogin-demo.test/<random>`) — that's today's
lure link. It's stable across restarts as long as you don't delete the lure, but the `run/config`
directory is gitignored/local, so generate it fresh each time you set up on a new machine.

**Terminal 2 — generate the live MFA code when needed:**

```bash
oathtool --totp -b <TOTP secret from the session's Academic Instruction in the LMS>
```

Codes expire every ~30s — run it right when the MFA screen appears, not before.

**In front of the class, in a private/incognito window of the Kali VM's browser** (Firefox ESR,
preinstalled — a private window keeps the demo from reusing any cached session):

1. Open the lure URL.
2. Click through the certificate warning — explain this is only because we skipped getting a real
   certificate for a throwaway local domain; a real attacker would use a real certificate (Let's
   Encrypt is free and automatic) and this warning would not appear. Don't let students think the
   warning is what would normally tip someone off.
   - Firefox: "Advanced..." → "Accept the Risk and Continue".
   - Chrome (if you're demoing from Chrome instead): "Advanced" → "Proceed to ... (unsafe)".
3. Log in with the UPN + password from the session's Academic Instruction in the LMS.
4. When prompted for a code, switch to Terminal 2, run `oathtool`, type the code in.
5. You land on a normal-looking Microsoft 365 page (`m365.cloud.microsoft`) — login succeeded, from
   the victim's point of view nothing was wrong.

**Show the capture, back in Terminal 1:**

```
sessions
```

Find the newest row — `tokens` column should say `captured` (green). Then:

```
sessions <id>
```

This prints the captured username, password, and the actual session cookie JSON
(`ESTSAUTH` / `ESTSAUTHPERSISTENT`) — the thing that's actually dangerous, not the password.

**Optional, if you want to go one step further live:** import that cookie JSON into a *different*,
never-logged-in browser profile using the StorageAce extension (link printed right after the JSON)
and navigate to `https://www.office.com` — you're in, no login screen at all. This is the most
convincing moment: MFA was done correctly by the real user, and it didn't matter.

## 4. After class

- `exit` the Evilginx2 console (Ctrl-C also works) to stop it.
- Nothing needs resetting — the demo account's password/MFA stay as-is between sessions,
  the lure URL stays valid, and `/etc/hosts` entries are harmless to leave in place.
- If you want a transcript of what was captured, `sessions <id>` and screenshot it before exiting —
  the lure's session list persists in `run/config` (local only, not committed) but isn't backed up
  anywhere.

## 5. If something breaks mid-demo

- **Stuck on a `This site can't be reached` / `DNS_PROBE_FINISHED_NXDOMAIN` page partway through
  login:** Microsoft's sign-in flow added a new subdomain evilginx wasn't proxying. Check
  `phishlets get-hosts o365` at the `:` prompt, compare to `/etc/hosts`, add whatever's missing the
  same way `scripts/setup.sh` does, then fully restart evilginx (not just `disable`/`enable` — it
  only re-reads the phishlet file on startup).
- **Login completes fine but `sessions` shows `tokens: none`:** the session cookie names Microsoft
  uses changed again. Restart evilginx with `-debug` added to the launch command, log in again,
  and grep the console output for `session: .login.microsoftonline.com:` lines — that's evilginx
  telling you exactly which cookies it captured. Update `phishlets/o365.yaml`'s `auth_tokens`
  section to match (see `ENVIRONMENT-SETUP.md` for exactly this happening once already).
- **No MFA prompt at all:** per-user MFA enforcement on the demo account got turned off somehow
  (nothing in this tenant enforces MFA by default — see `ENVIRONMENT-SETUP.md` §1). Re-enable it at
  https://account.activedirectory.windowsazure.com/UserManagement/MultifactorVerification.aspx.

## 6. Running on macOS instead

Everything here was originally built and verified end-to-end on macOS before moving to Kali — if a
Kali VM isn't available, it works the same way with two substitutions:

- Setup: `brew install go oath-toolkit git` instead of `apt-get install golang-go oathtool git make`
  (macOS ships `make` already). Everything else in `scripts/setup.sh` (cloning/building evilginx2,
  the `/etc/hosts` entries) is identical — if you're not on Kali, run those steps by hand instead of
  via the script, or ask whoever maintains this to add a `--macos` branch to it.
- No port 53 gotcha — macOS doesn't run `systemd-resolved`, evilginx2's DNS server binds cleanly
  (though it's still unused by this demo either way).
- Browser: Safari or Chrome in a private window; certificate-warning wording in step 3 above is
  written for Chrome already.
