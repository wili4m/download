# vulKiller (vk)

**Author:** Wiliam de Freitas
**Documentation reference version:** 1.3.0 (release candidate)
**Project stages:**

- [Development](https://git.mop.equinix.com.br/wdefreitas/linux/-/tree/main/tools/vulKiller_patcher/development)
- [Release Candidate](https://git.mop.equinix.com.br/wdefreitas/linux/-/tree/main/tools/vulKiller_patcher/release-candidate)
- [Stable](https://git.mop.equinix.com.br/wdefreitas/linux/-/tree/main/tools/vulKiller_patcher/stable)

---

## Overview

**vulKiller (vk)** is a Bash-based automation tool built to standardize and simplify the installation of security (or general) updates on Linux servers, executed via **Vicarius VRX**.

The script:

- Detects available updates (security-only or general);
- Applies the updates automatically;
- Generates CSV reports as evidence, showing package versions before and after the process;
- Manages package exclusions (hold list);
- Checks whether a reboot is required and can schedule it automatically.

---

## Supported Operating Systems

| Family | Distributions |
|---|---|
| Debian-like | Debian, Ubuntu |
| RHEL-like | RHEL, CentOS, Oracle Linux (OL), Rocky Linux |

The OS is detected automatically from `/etc/os-release` (the `ID` and `VERSION_ID` fields). Systems outside this list cause the script to abort with an error.

---

## Prerequisites

- **Root** privileges (the script checks `$EUID` and aborts if not run as root);
- A working package manager (`apt` or `yum`);
- For **RHEL**: the system must be registered with **Red Hat Subscription Manager** (the script validates this before proceeding);
- Sufficient free disk space (see the thresholds table below).

---

## Key Features

- Automated package updates (general or security-only mode);
- Simulation mode (dry-run), with no changes actually applied;
- Package exclusion list (hold list), per server;
- CSV report generation for auditing (before/after);
- Disk space validation before starting the process;
- *Phased Updates* fix on Ubuntu (prevents false negatives for pending security patches);
- Automatic detection of reboot requirements (new kernel installed);
- Reboot scheduling with timezone conversion to BRT;
- Multi-distribution support (Debian-like and RHEL-like);
- Structured logging with trace ID, timestamp, and severity levels (INFO/WARN/ERROR).

---

## Directory and File Structure

| Path | Purpose |
|---|---|
| `/var/log/vulkiller/vulkiller.log` | Tool log file |
| `/var/log/vulkiller/reports/YYYY/MM/DD/` | Reports (evidence) generated on each run |
| `/etc/default/equinix/pkgs_hold/` | Directory of empty files named after packages to be held |
| `/etc/default/equinix/reboot_schedule/` | Directory holding a single empty file named `HHMM` to define the scheduled reboot time |
| `/run/vulkiller.lock` | Lock file used to prevent concurrent runs |
| `/etc/apt/apt.conf.d/99-Phased-Updates` | (Ubuntu) Config file created/validated to disable phased updates |

---

## Usage

```bash
# Run the update process (default mode, no interactive confirmation)
./vulKiller-rc.sh

# Simulate the process without applying any changes
./vulKiller-rc.sh --simulate

# Show the tool version
./vulKiller-rc.sh -v | -V | --version

# Show help
./vulKiller-rc.sh -h | -H | --help
```

Any unrecognized argument causes the script to print the help message and exit.

---

## Configuration Variables (Modals)

| Variable | Values | Description |
|---|---|---|
| `modal_keep_report_files` | `true` / `false` | Keeps (or removes) the CSV report files after execution |
| `modal_reboot_after_update` | `true` / `false` | Automatically reboots the server when a new kernel is installed. If `false`, only recommends a manual reboot |
| `modal_update_all_packages` | `true` / `false` | Defines whether all available updates are applied (`true`) or only security updates (`false`), while still honoring held packages |
| `modal_convert_server_time_to_brt` | `true` / `false` | Converts the scheduled reboot time to the BRT timezone (America/Sao_Paulo) when the server uses a different timezone |

### Disk Space Thresholds (minimum required)

| Mount point | Minimum required (MB) |
|---|---|
| `/` | 1024 |
| `/boot` | 100 |
| `/boot/efi` | 100 |
| `/var` | 1024 |
| `/usr` | 1024 |
| `/tmp` | 100 |

The check only applies to mount points that actually exist as separate partitions on the host (validated via `df`).

---

## Execution Flow

1. **Execution validation**: checks root privileges and acquires a lock (`flock`) to prevent concurrent instances.
2. **Argument parsing**: `--simulate`, `-v`/`--version`, `-h`/`--help`, or default execution.
3. **Information banner**: tool name, version, stage, hostname, OS, OS version, uptime.
4. **Disk space validation** on the relevant mount points.
5. **Repository preparation**:
   - Ubuntu: ensures phased updates are disabled;
   - Debian/Ubuntu: runs `apt update`;
   - RHEL-like: validates subscription registration (RHEL only).
6. **Generates the available-updates report** (`*_updates_available.csv`).
7. **Calculates the total update size** and compares it against the available disk space on `/usr`.
8. **Processes the hold list** (`func_pkgs_to_avoid_update`): identifies packages to keep and applies the hold (via `apt-mark hold` or `--exclude` on yum).
9. **Runs the update** (`func_perform_update`): general or security-only, depending on the configured modal.
10. **Generates the evidence report** (`*_updates_performed.csv`), with before/after versions.
11. **Cleans up temporary files** (`func_cleanup`), honoring `modal_keep_report_files`.
12. **Checks and, if enabled, schedules a reboot** (`func_reboot_server`).
13. **Final summary**, with status, start/end times, and the number of packages updated.

---

## Evidence Reports (CSV)

### Available updates

**Debian/Ubuntu:**
```
Package;Current Version;Available Version
```

**RHEL-like:**
```
Advisory (Errata);Package
```

### Performed updates

**Debian/Ubuntu:**
```
Package Name ; Old version ; New version
```

**RHEL-like:**
```
Package old version ; Package new version
```

Reports are stored under `/var/log/vulkiller/reports/YYYY/MM/DD/`, named with date, trace ID, and hostname.

---

## Logging

Format of each log line:
```
[YYYY-MM-DD HH:MM:SS (TZ)] [traceid] [LEVEL] message
```

Levels used: `INFO`, `WARN`, `ERROR` (and `SIMULATION` when run with `--simulate`).

Log output modes (`func_log`):

| Mode | Behavior |
|---|---|
| `both` | Writes to the log file **and** prints to the screen (used as evidence via VRX) |
| `file` | Writes only to the log file |
| `screen` | Prints only to the screen |
| `silent` | Neither writes nor prints |

---

## Reboot Policy

- Reboot is only evaluated if `modal_reboot_after_update=true`.
- The need for a reboot is detected by:
  - **Debian/Ubuntu**: presence of `/var/run/reboot-required`, or by comparing the running kernel with the most recently installed one;
  - **RHEL-like**: via `grubby` (when available), or by comparing the installation date of the latest kernel with the last boot date.
- If a valid schedule exists in `/etc/default/equinix/reboot_schedule/` (a single file, in `HHMM` format), the reboot honors that time; otherwise, it is scheduled 5 minutes after execution.
- **Schedule safety rules**:
  - Multiple schedule files → the reboot is **aborted**;
  - A filename outside the valid `HHMM` format → the reboot is **aborted**;
  - In `--simulate` mode, the reboot is never actually performed, only reported.

---

## Security Features

| Feature | Description |
|---|---|
| Root privilege requirement | Prevents execution by an unprivileged user |
| Single-instance lock (`flock`) | Prevents concurrent updates and state corruption |
| Simulation mode (`--simulate`) | Allows validating the process without applying changes |
| Package hold list | Protects critical packages from unwanted updates |
| Preservation of local configuration | Uses `--force-confdef`/`--force-confold` with `apt` |
| RHEL registration validation | Prevents update attempts on an unlicensed system |
| Ubuntu Phased Updates fix | Prevents false negatives for pending security patches, validated via MD5 checksum of the config file |
| Disk space validation | Prevents failures/corruption caused by full disks during patching |
| Audit trail (evidence reports) | CSVs with before/after versions for compliance evidence |
| Structured logging with trace ID | Traceability for every execution |
| Strict reboot schedule validation | Aborts on multiple schedules or invalid format |
| Warning to logged-in users before reboot | Broadcast via `shutdown -r`, giving users time to save their work |
| File type validation before removal | Uses `file` to confirm the target is text before `rm -f`, preventing accidental removal of binaries |

---

## Error Handling and Exit Codes

The script uses only two exit codes:

| Code | Meaning |
|---|---|
| `0` | Execution completed successfully (including simulations and cases with no pending updates) |
| `1` | Failure at any stage (insufficient privileges, active lock, unsupported OS, insufficient disk space, repository failure, reboot scheduling failure, etc.) |

All failures are logged at the `ERROR` level before the script exits.

---

## Known Limitations

- Supports only the distributions listed under "Supported Operating Systems";
- Only one reboot schedule can exist at a time in `/etc/default/equinix/reboot_schedule/`;
- Reboot scheduling confirmation depends on `systemd` (`/run/systemd/shutdown/scheduled`).

---

## Version History

| Version | Stage | Notes |
|---|---|---|
| 1.3.0 | Release Candidate | Version documented in this README |

---

## Author

Wiliam de Freitas <wdefreitas@equinix.com>
