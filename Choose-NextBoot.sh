#!/usr/bin/env bash
set -euo pipefail

# Re-exec with sudo if not root
if [[ $EUID -ne 0 ]]; then
  exec sudo --preserve-env=PATH "$0" "$@"
fi

command -v efibootmgr >/dev/null 2>&1 || {
  echo "efibootmgr not found. Install it (on Ubuntu/Pop!: sudo apt install efibootmgr)" >&2
  exit 1
}

echo "=== EFI status ==="
efibootmgr | sed 's/^/  /'
echo

mapfile -t lines < <(efibootmgr -v)

# Parse Boot entries into arrays: IDS[], LABELS[], PATHS[]
IDS=()
LABELS=()
PATHS=()

while IFS= read -r line; do
  [[ $line =~ ^Boot([0-9A-Fa-f]{4})(\*)?[[:space:]]+(.*)$ ]] || continue
  bootnum="${BASH_REMATCH[1]}"

  # Extract label: tokens after "BootNNNN[*]" up to first token that starts with HD(
  # Then extract file path inside File(\... )
  # 1) label
  label=$(awk '
    /^Boot[0-9A-Fa-f]{4}/ {
      # drop first field (BootNNNN*), collect until token starts with "HD("
      $1=""; sub(/^ +/,"");
      out="";
      for(i=1;i<=NF;i++){
        if ($i ~ /^HD\(/) break;
        out = (out ? out " " : "") $i
      }
      print out
    }' <<<"$line")

  # 2) file path (may be absent for weird entries)
  path=$(sed -n 's/.*File(\(.*\)).*/\1/p' <<<"$line")
  [[ -z "$path" ]] && path="<no File() path>"

  IDS+=("$bootnum")
  LABELS+=("$(echo -n "$label" | sed 's/[[:space:]]\+$//')")
  PATHS+=("$path")
done < <(printf "%s\n" "${lines[@]}")

if (( ${#IDS[@]} == 0 )); then
  echo "No EFI boot entries found."
  exit 1
fi

echo "=== Select the entry to use for the NEXT boot (BootNext) ==="
printf "%3s  %-6s  %-40s  %s\n" "#" "ID" "Label" "Path"
echo "---- ------ ---------------------------------------- -----------------------------------------"
for i in "${!IDS[@]}"; do
  printf "%3d  %s   %-40s  %s\n" "$((i+1))" "${IDS[$i]}" "${LABELS[$i]:0:40}" "${PATHS[$i]}"
done

echo
read -rp "Enter number (1-${#IDS[@]}) to set as BootNext (or 'q' to quit): " sel
[[ "$sel" =~ ^[Qq]$ ]] && { echo "Aborted."; exit 0; }
if ! [[ "$sel" =~ ^[0-9]+$ ]] || (( sel < 1 || sel > ${#IDS[@]} )); then
  echo "Invalid selection." >&2
  exit 1
fi

idx=$((sel-1))
bootid="${IDS[$idx]}"
label="${LABELS[$idx]}"

echo
echo "Setting BootNext to Boot$bootid  ($label)"
efibootmgr -n "$bootid"

echo
echo "=== New EFI status ==="
efibootmgr | sed 's/^/  /'

read -rp "Reboot now to use BootNext? [y/N]: " ans
if [[ "$ans" =~ ^[Yy]$ ]]; then
  echo "Rebooting..."
  systemctl reboot
fi
