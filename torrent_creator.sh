#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/movies.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/series.sh"

common_init

main_menu() {
  while true; do
    echo
    echo "================ Torrentarr v5 ================"
    echo "MEDIA_ROOT  : $MEDIA_ROOT"
    echo "OUTPUT_ROOT : $OUTPUT_ROOT"
    echo "DRY_RUN     : $DRY_RUN"
    echo "----------------------------------------------------"
    echo " 1) Movies"
    echo " 2) Series"
    echo " 0) Quit"
    read -r -p "Select: " c
    case "$c" in
      1) movies_menu ;;
      2) series_menu ;;
      0) exit 0 ;;
      *) echo "Invalid" ;;
    esac
  done
}

main_menu
