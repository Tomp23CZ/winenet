#!/usr/bin/env bash
#---META---
set -e
REPO_URL="https://github.com/Tomp23CZ/winenet.git"
TMP_DIR="$(mktemp -d -t winenet.installer.XXXXXX)" || exit 1
trap 'rm -rf "$TMP_DIR"' EXIT
WINENET_FILE_PATH="$TMP_DIR/winenet.sh"

#---HELPERS---
get_user_bool() {
    local prompt="${1:-Continue?}"
    local response

    while true; do
        read -r -p "$prompt [Y/n]: " response </dev/tty || return 1
        response="${response:-Y}"

        case "$response" in
            [yY]|[yY][eE][sS]) return 0 ;;
            [nN]|[nN][oO]) return 1 ;;
            *) printf '%s\n' "Invalid response. Please enter 'y' or 'n'." >&2 ;;
        esac
    done
}

install_templates() {
  rm -rf "$WINENET_DATA_DIR/Templates"
  mkdir -p "$WINENET_DATA_DIR/Templates"
  cp -r "$TMP_DIR/Templates/." "$WINENET_DATA_DIR/Templates"
  local dir
  for dir in "$WINENET_DATA_DIR/Templates"/*/; do
    [[ -f "$dir/.template.config/template.json" ]] || continue
    dotnet new install "$dir"
  done
  printf "%s\n" "Templates installed"
}

#---ACTUAL-SCRIPT---
printf "%s\n" "Installing winenet..."
git clone "$REPO_URL" "$TMP_DIR"

source "$WINENET_FILE_PATH"
mkdir -p "$WINENET_SCRIPT_EXPECTED_DIR"
install -m 755 "$WINENET_FILE_PATH" "$WINENET_SCRIPT_EXPECTED_FILE"
printf "%s\n" "Script installed"

printf "%s\n" "Setting up $WINENET_NAME"
"$WINENET_SCRIPT_EXPECTED_FILE" setup
printf "%s\n" "$WINENET_NAME $WINENET_VERSION has been setup"

if get_user_bool "Would you like to install dotnet $WINENET_NAME templates?"; then
  install_templates
fi

printf "%s\n" "Installation complete"
