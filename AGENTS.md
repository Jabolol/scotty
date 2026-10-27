# Scotty

Menu bar app and `scotty` CLI for CMU's Campus VPN (split tunnel over openconnect, CMU single sign-on with Duo) and the
Andrew Kerberos ticket.

## Agents

- Run `scotty ensure` before reaching any CMU host. It returns at once when the tunnel is up; otherwise it signs in
  unattended (password filled from the Keychain, Duo remembered) within `--timeout` seconds (default 90).
- Exit codes:
  - `0` connected
  - `1` failed: read stderr
  - `2` usage
  - `3` a person must approve Duo or sign in: tell the user once and stop
- Never rerun `ensure` or `connect` in a loop: each attempt can send a Duo push, and repeated password failures lock
  the account.
- `scotty wait --timeout <s>` blocks until a sign-in started elsewhere finishes.
- `scotty status --json` prints `connected`, `wanted`, `signingIn`, `interface`, `address`, `since`, `expires`
  (session end), `idleTimeout` and `ticket` (`principal`, `expires`).
- `scotty ticket` renews the Kerberos ticket and delegates it to every host in the hosts file.
- "Password incorrect" from Kerberos means the Keychain entry is stale: tell the user and do not retry.
- Clock skew errors mean the system clock is off; "Cannot contact any KDC" is a network or DNS problem.
- Never switch to the Full VPN group, change system DNS, or run Cisco Secure Client at the same time.

## Unattended

The menu bar app keeps access up while the Mac runs:

- One reconnect per drop, once the network is back.
- In the last 10 minutes of a session, a reconnect while traffic is quiet.
- Kerberos: `kinit -R` when under 2 hours remain, the Keychain password when that fails, then delegation to every host
  in the hosts file after each renewal and each connect.

## Setup

- `./install.sh` builds the app into `~/Applications/Scotty.app`, links `~/.local/bin/scotty`, and installs the root
  helper in `/usr/local/libexec/scotty` with its sudoers rule.
- Keychain: a generic password with service `Scotty` and the Andrew ID as account.
- Hosts file: `~/Library/Application Support/Scotty/hosts`, one SSH host per line.

## Checks

- `swift format lint --strict -r Sources Package.swift`, configured by `.swift-format`; `swift format -i -r Sources
  Package.swift` fixes formatting.
- `swift build -c release` with no warnings, and `bash -n` on `install.sh` and `Root/*`.

## Layout

- `Sources/ScottyKit`: gateway, sign-in, tunnel, Kerberos, connection activity.
- `Sources/ScottyApp`: the menu bar app; `App` owns the status item and menu, `Model` the connection and traffic
  state, `Views` the menu rows.
- `Sources/scotty`: the CLI.
- `Bundle`: Info.plist, the Icon Composer app icon and the status bar glyphs.
- `Root/tunnel`: starts and stops openconnect as root.
- `Root/routes`: openconnect's connect script; split routes only, CMU DNS zones, session state.
