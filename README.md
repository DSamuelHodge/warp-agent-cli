# Warp Agent CLI for Termux (Android)

**Disclaimer:** This project is an unofficial community workaround to run Warp Agent CLI on Android devices via Termux using a lightweight Ubuntu PRoot container environment.

This repository provides an automated installation script that provisions a standard Linux glibc sub-environment inside Termux, installs the aarch64 ARM64 Warp Agent CLI binary, installs [Tailcat](https://github.com/tailscale/tailcat) for the agent to use as a tool, and wires a Termux:API bridge so Warp can call on-device Android APIs.

## Quick Start (One-Line Installer)

Open Termux on your Android device and paste the following command:

```bash
curl -sL https://raw.githubusercontent.com/DSamuelHodge/warp-agent-cli/main/setup.sh | bash
```

Once installation finishes, you can immediately begin using Warp Agent CLI right from your standard Termux prompt.

## Prerequisites

Before running the installer, ensure your environment meets these requirements:

1. **Android Device Architecture:** arm64 / aarch64 (most modern Android smartphones and tablets).
2. **Termux Installed from F-Droid or GitHub:**
   - Do **not** use the version from Google Play Store (it is deprecated and lacks updated package repositories).
   - Download the latest release from [F-Droid](https://f-droid.org/packages/com.termux/) or [Termux GitHub Releases](https://github.com/termux/termux-app/releases).

## Usage Guide

### 1. Authenticate Your Account

Before running agent tasks, connect your Warp account:

```bash
warp-agent login
```

Follow the link output in the terminal to complete sign-in in your mobile browser.

### 2. Launch the AI Agent

Start the interactive Warp Agent CLI session anytime:

```bash
warp-agent
```

You can pass arguments or commands directly to the agent as well:

```bash
warp-agent "Explain the directory structure of this project"
```

### 3. Access Full Ubuntu Shell

If you want to perform direct Linux terminal work inside the underlying PRoot container:

```bash
proot-distro login ubuntu --bind "$HOME/.warp-termux-api:/bridge"
```

## Quick Launch Shortcut

You do **not** need to run `proot-distro login ubuntu` every time. The installer already creates a global `warp-agent` command in Termux `$PREFIX/bin` that starts the Termux:API bridge and wraps:

```bash
proot-distro login ubuntu --bind "$HOME/.warp-termux-api:/bridge" -- exec warp
```

After `setup.sh` finishes, this works from a normal Termux prompt:

```bash
warp-agent
warp-agent login
warp-agent "Explain the directory structure of this project"
```

### Optional: add a shell alias instead

If you prefer an alias in your main Termux `.bashrc` or `.zshrc` (for example after a manual install):

```bash
echo 'alias warp-agent="proot-distro login ubuntu --bind \"$HOME/.warp-termux-api:/bridge\" -- exec warp"' >> ~/.bashrc
source ~/.bashrc
```

For zsh, append to `~/.zshrc` instead of `~/.bashrc`. The installer wrapper is preferred because it works in any shell without sourcing rc files.

## Tailcat

The installer puts the official **linux arm64** Tailcat binary inside Ubuntu (glibc) and a `tailcat` wrapper in Termux `$PREFIX/bin`. Warp can call `tailcat` directly as a shell tool. A listener is **not** started for you.

```bash
# inbound tunnel to Termux sshd (if you enabled 8022), or any local port
tailcat serve --key=default 8022

# auth-free Tailcat SSH into the Ubuntu shell that is running the listener
tailcat serve no-auth-ssh

# from another machine that also has Tailcat
tailcat ssh tcXXXXXXXXX
tailcat ping tcXXXXXXXXX
```

Share the printed `tc…` address out of band. `no-auth-ssh` is authenticated only by possession of that token; prefer a saved key and `tailcat serve --allow=nodekey:…`.

Keep a dedicated Termux session (or `termux-wake-lock`) for `tailcat serve`. Do not start the listener only inside a `warp-agent` session — it dies when the agent exits.

## Termux:API from Warp

Warp runs inside Ubuntu PRoot, so it cannot exec Termux’s Bionic `termux-*` helpers directly. The installer adds a host bridge:

1. Termux package `termux-api` plus the **Termux:API Android app** (F-Droid or GitHub, same source as Termux).
2. Host daemon `warp-termux-api-bridge` (started automatically by `warp-agent`).
3. Ubuntu command `termux-api`, mounted at `/bridge`.

From Warp (or an Ubuntu shell launched via `warp-agent`):

```bash
termux-api battery-status
termux-api toast -- "build finished"
termux-api clipboard-get
termux-tts-speak "hello"
termux-vibrate
termux-location
```

Grant the matching Android permissions in Termux:API. The bridge allowlists `termux-*` API commands only.

## SSH Access From Other Devices

The installer does **not** start an SSH server. Termux cannot bind privileged port **22** without root, so inbound SSH uses **8022** by default.

PRoot Ubuntu shares Android's network stack. One Termux `sshd` on `8022` is enough for other devices to reach the phone, then launch `warp-agent` from that session.

### 1. Enable inbound SSH on the phone (Termux)

```bash
pkg install -y openssh
passwd                  # set the Termux user password
whoami                  # note this username (usually u0_aXXX, not root)
sshd                    # listens on 8022
```

Find the LAN address:

```bash
ip -4 addr show wlan0
```

Keep Termux alive while you use SSH:

```bash
termux-wake-lock
```

Optional persist: `pkg install termux-services && sv-enable sshd`, or add `sshd` to `~/.bashrc`.

### 2. Connect from another device on the same Wi-Fi

```bash
ssh -p 8022 u0_aXXX@PHONE_LAN_IP
```

Once inside Termux:

```bash
warp-agent
# or
proot-distro login ubuntu --bind "$HOME/.warp-termux-api:/bridge"
```

SFTP uses the same port:

```bash
sftp -P 8022 u0_aXXX@PHONE_LAN_IP
```

Prefer key auth:

```bash
# on the phone
mkdir -p ~/.ssh && chmod 700 ~/.ssh
nano ~/.ssh/authorized_keys   # paste the other device's public key
chmod 600 ~/.ssh/authorized_keys
```

### 3. Outbound SSH from the phone

Both Termux and the Ubuntu container can reach other machines on the LAN or internet with a normal client (no extra port):

```bash
# from Termux
ssh user@other-device

# from Ubuntu
proot-distro login ubuntu -- ssh user@other-device
```

### 4. Optional: second listener inside Ubuntu

Only needed if you want to SSH **directly** into the PRoot root shell instead of Termux first. Use a different high port so it does not collide with Termux `8022`:

```bash
proot-distro login ubuntu -- bash -c '
  apt-get update -y
  apt-get install -y openssh-server
  mkdir -p /run/sshd
  sed -i "s/^#\?Port .*/Port 8023/" /etc/ssh/sshd_config
  sed -i "s/^#\?PermitRootLogin .*/PermitRootLogin yes/" /etc/ssh/sshd_config
  ssh-keygen -A
  passwd
  /usr/sbin/sshd
'
```

Then from another device:

```bash
ssh -p 8023 root@PHONE_LAN_IP
```

`sshd` inside PRoot dies if that login session exits, so the Termux `8022` path is more reliable.

### 5. Off-LAN / true bidirectional reachability

Carrier NAT and most home routers block inbound `8022` from the internet. Do **not** forward port 22. Options that work without root:

- Same Wi-Fi: `ssh -p 8022 user@PHONE_LAN_IP`
- Away from home: Tailcat (`tailcat serve`), Tailscale, ZeroTier, or a reverse tunnel from the phone
- Agent web servers (`localhost:3000`, etc.) are already reachable in the phone browser; from another device use `http://PHONE_LAN_IP:PORT` on the same LAN, or the mesh VPN IP off-LAN

Android may still kill Termux in the background. Disable battery optimization for Termux and hold a wake lock.

## How It Works

Base Termux uses Android's native Bionic libc standard library instead of glibc. Desktop and server binaries compiled for general ARM64 Linux (such as Warp Agent CLI) cannot execute natively in base Termux without runtime modifications.

This repository solves that limitation automatically:

1. **Verifies Environment:** Ensures you are executing on an ARM64 Android device running Termux.
2. **Installs PRoot Distro:** Installs `proot-distro` to create an isolated Ubuntu ARM64 userspace.
3. **Deploys Warp Agent:** Ingests the official Debian `.deb` ARM64 package from Warp inside the Ubuntu container.
4. **Installs Tailcat:** Places the official linux arm64 Tailcat package in Ubuntu and a Termux wrapper so both you and Warp can use it.
5. **Bridges Termux:API:** Runs allowlisted `termux-*` commands on the Termux host and exposes them to Warp as `termux-api`.
6. **Creates Wrapper Shortcut:** Adds `warp-agent` in Termux `$PREFIX/bin`, binds `~/.warp-termux-api` at `/bridge`, and starts the API daemon.

## Recommended Tips & Workarounds

- **Storage & File Performance:** For maximum file watching speed and minimal permission friction, store project repositories within the PRoot root environment (`/root/`) or inside Termux local storage (`/data/data/com.termux/files/home`).
- **Web Server Ports:** Local servers launched by agent commands (e.g. `npm run dev` or Python HTTP servers) share localhost with Android. You can test them directly inside Chrome/Brave at `http://localhost:<port>`.
- **Updating the Agent:** To update Warp CLI in the future, run:

```bash
proot-distro login ubuntu -- bash -c "apt-get update && apt-get install --only-upgrade warp"
```

## Repository File Layout

```text
warp-agent-cli/
├── setup.sh     # Automated installation script (Warp, Tailcat, Termux:API bridge)
├── README.md    # Getting started documentation
└── LICENSE      # MIT License
```

## License

MIT License. See [LICENSE](LICENSE) for details.
