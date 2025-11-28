# openconnect-toggle

`openconnect-toggle` is a small macOS helper script that makes it easy to:

- connect to and control **OpenConnect VPN** sessions;
- work with a simple server setup where the client only has:
  - the server **CA certificate**,
  - a **username**,
  - and a **password**.

You can:

- run the script in **CLI mode** from Terminal,
- run it with a **double-click** in Finder (as a `.command` file) from any directory,
- optionally view status and control connections via the excellent **SwiftBar** GUI in the macOS menu bar.

For a quick initial setup it is recommended to:

1. save your CA certificate in **X.509** format under the name `ca.crt`,
2. put `ca.crt` **next to the script**.

However, this is not required: during interactive setup you can instead paste an **absolute path** to your existing certificate file without renaming it.

---

## Features

- **Single toggle command**: `openconnect-toggle <username>`  
  - If VPN is disconnected → connect as `<username>`.  
  - If VPN is connected for that user → disconnect.
  - If VPN is connected for another user → disconnect and connect as `<username>`.

- **Status output**:
  - shows `VPN connected for username@server.` or `VPN disconnected.`,
  - prints active VPN interface (e.g. `utun0`) and tunnel IP (e.g. `10.x.x.x`).

- **SwiftBar integration** (optional, guided interactively):
  - menu bar icon showing connection status (🔒 / 🔓),
  - per-user toggle menu items,
  - an `Add user…` item,
  - auto-starts SwiftBar after integration (if possible).

- **Touch ID for sudo** (optional):
  - can add `auth sufficient pam_tid.so` at the top of `/etc/pam.d/sudo`,
  - remembers if *this script* added the line (`TOUCHID_ADDED=1`),
  - `-uninstall` can roll it back if the config is still present.

- **Secure credentials**:
  - VPN passwords are stored only in **Keychain** (as generic password items),
  - keyed by `account = <username>`, `service = openconnect:<server>`.

- **Centralized config & CA**:
  - config and CA live in:
    - `~/Library/Application Support/openconnect-toggle/`
  - SwiftBar plugin directory contains **only the plugin script**, not config or certs. The plugin script is exactly the same original script but with different name, it uses the same shared config.

- **Reset & uninstall helpers**:
  - `-reset`: remove config + Keychain entries for known users (saved in the config).
  - `-uninstall`: everything `-reset` does, plus optional cleanup of SwiftBar plugin, logs, SwiftBar app, and PAM Touch ID changes.

> ⚠️ This script is intended for advanced users. It touches PAM (optionally) and uses `sudo`. Read carefully before using in security-critical environments.

---

## Requirements

- **macOS** (recent versions with SwiftBar support).
- **Homebrew** (recommended) for installing:
  - `openconnect`
  - `swiftbar` (optional, for the menu bar GUI)

Install OpenConnect:

    brew install openconnect

Optional: install SwiftBar:

    brew install --cask swiftbar

---

## Installation

### 1. Clone the repository

    git clone https://github.com/<your-username>/openconnect-toggle.git
    cd openconnect-toggle

### 2. Make the script executable

    chmod +x openconnect-toggle.command

You can:

- run it directly from the repository directory, or
- copy/move `openconnect-toggle.command` anywhere you like (for example, `~/bin` or your Desktop for double-click usage).

---

## First run (CLI, interactive setup)

Run the script **without arguments** from Terminal or just double-click it:

    ./openconnect-toggle.command

On first run, it will guide you through:

1. **VPN server hostname**  
   Example: `vpn.example.com`.

2. **Path to CA certificate file**  
   - Default: `ca.crt`.
   - If you just press Enter, it will look for `ca.crt` **next to the script**.
   - If you provide a relative path (for example, `certs/ca.crt`), it is treated as **relative to the script directory**, not the current working directory. An absolute path will work as it is.
   - The certificate is copied into:

        ~/Library/Application Support/openconnect-toggle/<original-file-name>.crt

     and the filename is stored in the config as `CA_FILE`.

3. **First VPN user**  
   - The script will ask for a **username**.
   - It will then ask for the corresponding password and store it in **Keychain** as:
     - `account = <username>`
     - `service = openconnect:<server>`

4. **Optional: enable Touch ID for sudo**  
   - The script may offer to enable Touch ID for `sudo` by inserting:

        auth       sufficient     pam_tid.so

     at the top of `/etc/pam.d/sudo`.
   - If you accept:
     - the script records that it added this line (`TOUCHID_ADDED=1` in config),
     - `-uninstall` will later be able to remove it.
   - If you decline:
     - it records `TOUCHID_DENIED=1` and will not ask again,
     - you can reset this behavior by removing the config (for example, with `-reset`).

5. **Optional: SwiftBar integration**  
   - The script can set up a SwiftBar plugin:
     - if SwiftBar is not installed, it can install it via Homebrew (if available),
     - you will be asked for the SwiftBar **plugins directory**, default:

          ~/Library/Application Support/SwiftBar/plugins

     - the script then copies itself into that directory as:

          openconnect-toggle.1m.sh

       and marks it executable with `chmod +x`.
     - if SwiftBar is not running, the script will try to start it:

          open -a "SwiftBar"

After initial setup, running the script **without arguments** in Terminal will:

- show the current VPN status (connected/disconnected, interface and IP),
- without re-running the setup (unless the config is deleted).

---

## Config and storage layout

The script uses the following locations:

- **Config directory**  

      ~/Library/Application Support/openconnect-toggle/

- **Config file**  

      ~/Library/Application Support/openconnect-toggle/openconnect-toggle.cfg

- **CA certificate copy**  

      ~/Library/Application Support/openconnect-toggle/<your-ca-file-name>.crt

- **Log file**  

      ~/Library/Logs/openconnect-toggle.log

- **PID file** for the `openconnect` process  

      ~/.openconnect.pid

Passwords are **never stored** in the config file — only in Keychain.

Example config (simplified):

    SERVER=vpn.example.com
    CA_FILE=ca.crt
    TOUCHID_DENIED='0'
    TOUCHID_ADDED='1'
    SWIFTBAR_INSTALLED='1'
    SWIFTBAR_DENIED='0'
    SWIFTBAR_PLUGIN_PATH='/Users/you/Library/Application Support/SwiftBar/plugins/openconnect-toggle.1m.sh'
    CURRENT_USER='youruser'
    USER_youruser='1'
    USER_someoneelse='1'

---

## Usage (CLI)

### Status (no arguments)

    ./openconnect-toggle.command

Interactive terminal:

- if configured, prints something like:

      VPN connected for username@server.
      Interface: utun3
      VPN IP: 10.x.x.x

  or:

      VPN disconnected.
      Interface: none
      VPN IP: none

- if not configured yet, this triggers the **interactive setup**.

### Toggle VPN for a user

    ./openconnect-toggle.command <username>

Behavior:

- If VPN is **disconnected**:
  - ensures a password for `<username>` exists in Keychain (prompts if missing),
  - starts `openconnect` in background with:
    - `--protocol=anyconnect`
    - `--user=<username>`
    - `--cafile=<CA_PATH>`
    - `--background`
    - `--pid-file=~/.openconnect.pid`
  - prints status.

- If VPN is **connected**:
  - sends `INT` to the `openconnect` process referenced by `~/.openconnect.pid`  
    (falling back to `killall openconnect` if needed),
  - clears `CURRENT_USER` in the config,
  - prints `VPN disconnected.` and interface/IP info.

### Add a new user

    ./openconnect-toggle.command adduser

- Must be run in an interactive terminal.
- Prompts for a **new username**.
- If needed, prompts for the password and stores it in Keychain.
- Marks the user in the config as `USER_<username>=1`.

---

## SwiftBar integration

If SwiftBar integration is enabled, the plugin script is created as:

    ~/Library/Application Support/SwiftBar/plugins/openconnect-toggle.1m.sh

SwiftBar periodically runs this script **without arguments**, which triggers the SwiftBar status mode:

- menu bar icon:
  - 🔒 = connected
  - 🔓 = disconnected

- status entries:
  - `Status: connected` / `Status: disconnected`
  - `Interface: utunX` / `Interface: none`
  - `VPN IP: 10.x.x.x` / `VPN IP: none`

- user-related actions:
  - one menu item per configured user:

        Toggle VPN (user1)
        Toggle VPN (user2)
        ...

    each of them runs:

        openconnect-toggle.command <user>

  - an `Add user...` menu item that launches Terminal and runs:

        openconnect-toggle.command adduser

CLI usage and SwiftBar usage share the same config and Keychain entries and can be used side by side.

---

## Touch ID for sudo (PAM)

When you allow the script to enable Touch ID, it:

- inserts at the top of `/etc/pam.d/sudo`:

      auth       sufficient     pam_tid.so

- records `TOUCHID_ADDED=1` in the config.

This allows you to confirm `sudo` operations with Touch ID (on supported Mac hardware).

### Security and behavior notes

- This affects **all `sudo` invocations** on your system, not just this script.
- If you later run `./openconnect-toggle.command -uninstall` **while the config still exists**, the script can detect `TOUCHID_ADDED=1` and offer to remove the line again.

If you delete the config (manually or via `-reset`), the script will no longer know whether it added the `pam_tid.so` line, and you will have to edit `/etc/pam.d/sudo` manually if you want to revert it.

---

## Sudoers example (optional)

By default, `sudo` behaves as usual (password or Touch ID, depending on your system).  
If you want to reduce password prompts **for this script’s actions only**, you can add a sudoers rule.

> ⚠️ Be careful with sudoers. A broken sudoers file can lock you out of `sudo`.  
> Always edit via `sudo visudo` and make sure you know what you’re doing.

Example: allow your user to run `openconnect`, `kill`, and `killall` without a password:

1. Run:

       sudo visudo

2. Add a line (adjust `yourusername` and paths as necessary):

       yourusername ALL=(root) NOPASSWD: /usr/local/bin/openconnect, /opt/homebrew/bin/openconnect, /bin/kill, /usr/bin/killall

Paths depend on your Homebrew prefix (for example, `/opt/homebrew/bin/openconnect` on Apple Silicon).

This is entirely optional.

---

## Reset and uninstall

### Reset

    ./openconnect-toggle.command -reset

This will:

- load the config (if present),
- remove **Keychain entries** for all known users:
  - `account = <username>`
  - `service = openconnect:<server>`
- delete the entire config directory:

      ~/Library/Application Support/openconnect-toggle/

**Important:**  
`-reset` deletes the configuration file, which also stores whether PAM settings were modified (`TOUCHID_ADDED=1`).  
After `-reset`, the script no longer knows whether it added `pam_tid.so` to `/etc/pam.d/sudo`, so if you later run `-uninstall`, it will **not** be able to automatically revert PAM changes. In that case, you must edit `/etc/pam.d/sudo` manually if you want to remove the Touch ID line.

### Uninstall

    ./openconnect-toggle.command -uninstall

Interactive only (must be run in a real terminal).

It will:

- behave like `-reset` (remove config + Keychain entries for known users),
- and additionally ask if you want to:
  - remove the **SwiftBar plugin** (if `SWIFTBAR_PLUGIN_PATH` is known),
  - remove the **log file**:

        ~/Library/Logs/openconnect-toggle.log

  - uninstall **SwiftBar** via Homebrew (if present),
  - remove `pam_tid.so` from `/etc/pam.d/sudo`, but **only if**:
    - `TOUCHID_ADDED=1` is in the config, and
    - the `pam_tid.so` line is found in the file.

It does **not**:

- delete the script file `openconnect-toggle.command`,
- delete your original CA certificate file (the one you used during setup).

---

## Development

The project consists of a single script file:

- `openconnect-toggle.command`

If you modify it:

- try to preserve backward compatibility of the config format,
- be especially careful with changes related to PAM and `sudo`.

---

## License

This project is licensed under the **GNU General Public License v3.0** (GPLv3) or later.

See the `LICENSE` file or the official text at:  
https://www.gnu.org/licenses/gpl-3.0.en.html
