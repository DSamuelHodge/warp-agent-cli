# Warp Agent CLI for Termux (Android)

**Disclaimer:** This project is an unofficial community workaround to run Warp Agent CLI on Android devices via Termux using a lightweight Ubuntu PRoot container environment.

This repository provides an automated installation script that provisions a standard Linux glibc sub-environment inside Termux, installs the aarch64 ARM64 Warp Agent CLI binary, and configures a global launcher command for seamless access.

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
proot-distro login ubuntu
```

## How It Works

Base Termux uses Android's native Bionic libc standard library instead of glibc. Desktop and server binaries compiled for general ARM64 Linux (such as Warp Agent CLI) cannot execute natively in base Termux without runtime modifications.

This repository solves that limitation automatically:

1. **Verifies Environment:** Ensures you are executing on an ARM64 Android device running Termux.
2. **Installs PRoot Distro:** Installs `proot-distro` to create an isolated Ubuntu ARM64 userspace.
3. **Deploys Warp Agent:** Ingests the official Debian `.deb` ARM64 package from Warp inside the Ubuntu container.
4. **Creates Wrapper Shortcut:** Adds a global shell executable (`warp-agent`) inside Termux's `$PREFIX/bin`, bridging commands seamlessly into the PRoot sub-shell.

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
├── setup.sh     # Automated installation script
├── README.md    # Getting started documentation
└── LICENSE      # MIT License
```

## License

MIT License. See [LICENSE](LICENSE) for details.
