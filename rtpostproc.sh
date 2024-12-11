#!/bin/bash

###########################################
#
# rtPostproc v3 - November 2024
#
# rTorrent postprocess script which unpacks
# and hardlinks downloaded files to an
# export directory for remote sync
#
###########################################

TEMP_DIR="[/path/to/temporary/dir]" # Directory in which torrent files are placed during processing
LOG_FILE="[path/to/log/file]" # Location of log file for this script
DEBUG_FILE="[/path/to/temp/debug/file]" # Temporary file which is dumped into main log if any errors occur

# Enter torrent labels on the left and their associated rTorrent download directories on the right
# Last entry is for torrents without labels, which are processed into a catch-all export directory
# Add more as needed; ensure all entries remain in double quotes 
declare -A LABEL_DOWNLOAD
LABEL_DOWNLOAD["[label]"]="/path"
LABEL_DOWNLOAD["[label]"]="/path"
LABEL_DOWNLOAD["[label]"]="/path"
LABEL_DOWNLOAD["[label]"]="/path"
LABEL_DOWNLOAD["Unlabeled"]="/path"


# Enter torrent labels on the left and their associated export directories on the right
# Last entry specifies the catch-all export directory
# Add more as needed; ensure all entries remain in double quotes 
declare -A LABEL_EXPORT
LABEL_EXPORT["[label]"]="/path"
LABEL_EXPORT["[label]"]="/path"
LABEL_EXPORT["[label]"]="/path"
LABEL_EXPORT["[label]"]="/path"
LABEL_EXPORT["Unlabeled"]="/path"

torrentname="$1"
torrentpath="$2"
torrentlabel="$3"

# Finding the top level directory of the torrent relative to LABEL_DOWNLOAD
# Single-file torrents will be moved to a directory matching the torrent's name to keep things tidy
torrent_tld=
if [[ -d "${torrentpath}" ]]; then
    torrent_tld="${torrentpath#"${LABEL_DOWNLOAD[${torrentlabel}]}"}"
else
    torrent_tld="/${torrentname}"
fi

# Set the Unlabeled key for torrents without labels
if [[ -z "${torrentlabel}" ]]; then
  torrentlabel="Unlabeled"
fi

# Function for log that indents multiple strings separated by double quotes to break up long messages
log() {
  local message1="$1"
  shift 1
  local -a remaining=( "$@" )
  echo "$(date '+%Y-%m-%d %H:%M:%S') - ${message1}" >> "${LOG_FILE}"
  local -i s; s=24
  for message in "${remaining[@]}"; do
    echo "$(printf %$s's\n')${message}" >> "${LOG_FILE}"
    s=$((s+2))
  done
}

# Dumps all trace messages from 'set -x' to main log
dump_debug() {
  echo "[ERROR] Error encountered. Dumping trace..." >> "${LOG_FILE}"
  cat "${DEBUG_FILE}" | while IFS=$'\n' read -r line; do
    echo "[DEBUG] - ${line}" >> "${LOG_FILE}"
  done
  log "Process exited with an error."
}

# Helper function for extracting files
# Change any options as desired
# As-is, unrar will run at low priority, preserve filetrees, and overwrite if files exist
extract_files() {
  local source="$1"
  local dest="$2"
  nice -n 16 unrar x -o+ "${source}" "${dest}" 2>> "${DEBUG_FILE}"
}

# Helper funciton for hardlinking non-rar files
# Change any options as desired
# cp will -u [u]pdate (overwrite) older existing files, -l hard [l]ink, 
#   and run in -a [a]rchival mode to preserve filetrees, metadata, etc.
hardlink_files() {
  local source="$1"
  local dest="$2"
  cp -ula "${source}" "${dest}" 2>> "${DEBUG_FILE}"
}

# Single file processing; drops files in a temporary directory
# This allows a torrent's files to remain unbothered by any syncing processeses which
#   watch the export directorry until the entire torrent is finished processing
process_files() {
  local label="$1"
  local subdir="$2"
  local process="$3"
  local file="$4"

  mkdir -p "${TEMP_DIR}${subdir}" 2>> "${DEBUG_FILE}"
  if [[ "${process}" == "x" ]]; then
    log "Unpacking archive ${file}" "to directory ${TEMP_DIR}${subdir}/"
    extract_files "${file}" "${TEMP_DIR}${subdir}/"
  elif [[ "${process}" == "l" ]]; then
    log "Hardlinking file ${file}" "to directory ${TEMP_DIR}${subdir}/"
    hardlink_files "${file}" "${TEMP_DIR}${subdir}/"
  fi
}

# Moves the torrent_tld and its contents from TEMP_DIR to the appropriate LABEL_EXPORT directory
move_to_export() {
  local label="$1"

  mkdir -p "${LABEL_EXPORT[${label}]}" 2>> "${DEBUG_FILE}"
  log "Moving directory ${TEMP_DIR}${torrent_tld}" "to ${LABEL_EXPORT[${label}]}/"
  mv "${TEMP_DIR}${torrent_tld}" "${LABEL_EXPORT[${label}]}/" 2>> "${DEBUG_FILE}"
}

find_files() {
  # Only designed to extract RAR archives; will not automatically extract any other archive formats
  # Edit the variable below to include regex for other archive types unrar can handle if needed
  # Will ignore SFV and split archive extensions (*.r01, etc) when hardlinking
  local find_rar="-iname '*.rar'"
  local find_nonrar="-type f ! -regex '.*\.\(r[a0-9][r0-9]\|sfv\|s[0-9][0-9]\|t[0-9][0-9]\|u[0-9][0-9]\)'"

  find "${torrentpath}" -mindepth 1 "${find_rar}" -print0 2>> "${DEBUG_FILE}" | while read -d $'\0' rarfile; do
    path="$(dirname "${rarfile}")"
    subdir="${path#"${LABEL_DOWNLOAD[${torrentlabel}]}"}"
    process_files "${torrentlabel}" "${subdir}" "x" "${rarfile}"
  done

  find "${torrentpath}" -mindepth 1 "${find_nonrar}" -print0 2>> "${DEBUG_FILE}" | while read -d $'\0' nonrarfile; do
    path="$(dirname "${nonrarfile}")"
    subdir="${path#"${LABEL_DOWNLOAD[${torrentlabel}]}"}"
    process_files "${torrentlabel}" "${subdir}" "l" "${nonrarfile}"
  done

  move_to_export "${torrentlabel}"
}

# Exit on encountering a torrent label not specified in the arrays above
if [[ ! -v LABEL_DOWNLOAD["${torrentlabel}"] ]]; then
  log "Encountered unrecognized label ${torrentlabel} for torrent ${torrentname}."
  echo >> "${LOG_FILE}"
  exit 0
fi

# Main script body
set -x
trap 'dump_debug; exit 1' ERR

# Clear the DEBUG_FILE before beginning
cat /dev/null > "${DEBUG_FILE}"

log "rTorrent postprocess beginning for ${torrentname}"

if [[ -d "${torrentpath}" ]]; then
  find_files
elif [[ "${torrentpath}" == *.rar ]]; then
  process_files "${torrentlabel}" "${torrent_tld}" "x" "${torrentpath}"
  move_to_export "${torrentlabel}"
else
  process_files "${torrentlabel}" "${torrent_tld}" "l" "${torrentpath}"
  move_to_export "${torrentlabel}"
fi

log "rTorrent postprocess complete!"
echo >> "${LOG_FILE}" # Add space in log between each execution for readability
