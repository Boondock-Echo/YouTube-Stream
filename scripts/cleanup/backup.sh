#!/bin/bash

# Safety Backup Script for YouTube-Stream Setup (Fixed: No incremental flag to avoid /dev/null error)
# Run as root/sudo. Creates /tmp/youtube-stream-backup-$(date +%Y%m%d).tar.gz
# Includes all key files/dirs with perms/ownership preserved.
# Excludes node_modules (large; rebuildable) and logs (noisy).

set -e  # Exit on error

BACKUP_DIR="/tmp"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/youtube-stream-backup-${TIMESTAMP}.tar.gz"

echo "Creating backup: ${BACKUP_FILE}"

# Key paths to include (based on repo + custom fixes)
declare -a PATHS=(
  "/var/lib/streamer/YouTube-Stream/scripts/"  # All scripts (configure_obs.sh, etc.)
  "/opt/youtube-stream/webapp/"                # React app (exclude node_modules for size)
  "/var/lib/streamer/.config/obs-studio/"      # OBS configs (scenes, profiles, global.ini)
  "/etc/youtube-stream/"                       # Env file/dir
  "/etc/systemd/system/react-web.service"      # Systemd units
  "/etc/systemd/system/obs-headless.service"
  "/var/lib/streamer/"                         # Streamer home (logs, but exclude .cache if huge)
)

# Create manifest
MANIFEST="/tmp/backup-manifest.txt"
echo "Backup Manifest - Created: $(date)" > "${MANIFEST}"
echo "User: streamer (ensure recreated with same UID/GID)" >> "${MANIFEST}"
echo "Key Paths:" >> "${MANIFEST}"
for path in "${PATHS[@]}"; do
  echo "  ${path}" >> "${MANIFEST}"
done
echo "" >> "${MANIFEST}"
echo "Exclusions: node_modules/, *.log, /dev/null (special files)" >> "${MANIFEST}"
echo "Restore: tar -xzf ${BACKUP_FILE} -C / && systemctl daemon-reload" >> "${MANIFEST}"

# Tar with perms/ownership (GNU tar; no --listed-incremental to fix /dev/null error)
tar --create \
    --gzip \
    --file="${BACKUP_FILE}" \
    --preserve-permissions \
    --same-owner \
    --exclude="**/node_modules" \
    --exclude="**/*.log" \
    --exclude="/dev/null" \
    --exclude="*.sock" \
    --transform='s|^|/|' \
    "${MANIFEST}" \
    "${PATHS[@]}"

echo "Backup complete: ${BACKUP_FILE}"
echo "Size: $(du -h "${BACKUP_FILE}" | cut -f1)"
echo "Manifest preview:"
cat "${MANIFEST}"
rm "${MANIFEST}"  # Clean up

# Optional: Verify extract perms
echo "Test extract (dry-run): tar -tzf ${BACKUP_FILE} | head -10"
