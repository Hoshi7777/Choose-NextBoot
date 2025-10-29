# Choose-NextBoot
An interactive CLI tool to list your UEFI boot entries and set one as the **next boot only** (`BootNext`) using `efibootmgr`. Handy for dual-boot setups where you want to reboot into Windows (or another OS) just once without changing your permanent boot order or having to spam your F keys to get into the GRUB menu.

## What it does
- Lists all EFI boot entries with IDs, labels, and their `File(\...)` paths
- Lets you select one to set as `BootNext` (one-time)
- Shows current `BootCurrent`, `BootOrder`, and `BootNext` before/after
- Re-invokes with `sudo` automatically if you’re not root

## Requirements
- Linux system with UEFI firmware
- `efibootmgr` installed  
  - Ubuntu: `sudo apt install efibootmgr`

## Install
1. Save the script:
   ```bash
   sudo tee /usr/local/bin/Choose-NextBoot.sh >/dev/null <<'EOF'
   #! /usr/bin/env bash
   set -euo pipefail
   if [[ $EUID -ne 0 ]]; then exec sudo --preserve-env=PATH "$0" "$@"; fi
   command -v efibootmgr >/dev/null || { echo "efibootmgr not found"; exit 1; }

   echo "=== EFI status ==="
   efibootmgr | sed 's/^/  /'
   echo

   mapfile -t lines < <(efibootmgr -v)
   IDS=(); LABELS=(); PATHS=()

   while IFS= read -r line; do
     [[ $line =~ ^Boot([0-9A-Fa-f]{4})(\*)?[[:space:]]+(.*)$ ]] || continue
     bootnum="${BASH_REMATCH[1]}"
     label=$(awk '/^Boot[0-9A-Fa-f]{4}/{
       $1=""; sub(/^ +/,""); out="";
       for(i=1;i<=NF;i++){ if ($i ~ /^HD\(/) break; out=(out?out" ":"")$i }
       print out
     }' <<<"$line")
     path=$(sed -n 's/.*File(\(.*\)).*/\1/p' <<<"$line"); [[ -z "$path" ]] && path="<no File() path>"
     IDS+=("$bootnum"); LABELS+=("$(echo -n "$label" | sed 's/[[:space:]]\+$//')"); PATHS+=("$path")
   done < <(printf "%s\n" "${lines[@]}")

   (( ${#IDS[@]} )) || { echo "No EFI boot entries found."; exit 1; }

   echo "=== Select the entry to use for the NEXT boot (BootNext) ==="
   printf "%3s  %-6s  %-40s  %s\n" "#" "ID" "Label" "Path"
   echo "---- ------ ---------------------------------------- -----------------------------------------"
   for i in "${!IDS[@]}"; do
     printf "%3d  %s   %-40s  %s\n" "$((i+1))" "${IDS[$i]}" "${LABELS[$i]:0:40}" "${PATHS[$i]}"
   done
   echo
   read -rp "Enter number (1-${#IDS[@]}) to set as BootNext (or 'q' to quit): " sel
   [[ "$sel" =~ ^[Qq]$ ]] && { echo "Aborted."; exit 0; }
   [[ "$sel" =~ ^[0-9]+$ ]] && (( sel>=1 && sel<=${#IDS[@]} )) || { echo "Invalid selection."; exit 1; }

   idx=$((sel-1)); bootid="${IDS[$idx]}"; label="${LABELS[$idx]}"
   echo; echo "Setting BootNext to Boot$bootid  ($label)"
   efibootmgr -n "$bootid" || { echo "Failed to set BootNext."; exit 1; }

   echo; echo "=== New EFI status ==="
   efibootmgr | sed 's/^/  /'

   read -rp "Reboot now to use BootNext? [y/N]: " ans
   [[ "$ans" =~ ^[Yy]$ ]] && { echo "Rebooting..."; systemctl reboot; }
   EOF

Make it executable:
chmod +x /usr/local/bin/Choose-NextBoot.sh

# Notes

BootNext is a one-time setting. It does not change your permanent BootOrder.

You must have firmware/BIOS in UEFI mode (not Legacy/CSM).

If you don’t see the OS you expect, ensure its EFI files exist on that disk’s ESP and that the entry is registered (efibootmgr -c ...).

# Troubleshooting

No such file or directory / No EFI entries: Booted in Legacy mode or missing ESP.

efibootmgr not found: Install it (sudo apt install efibootmgr).

Operation not permitted: Run the script without sudo; it re-execs itself with sudo.

# Security

The script uses sudo only for efibootmgr and reading EFI data. Inspect before installing if desired.
