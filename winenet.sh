#!/usr/bin/env bash 

#------METADATA------#
export WINENET_NAME="winenet"
export WINENET_VERSION="0.0.0"
export WINENET_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/$WINENET_NAME"
export WINENET_PREFIX="$WINENET_DATA_DIR/prefix"
export WINENET_SCRIPT_EXPECTED_DIR="$HOME/.local/bin"
export WINENET_SCRIPT_EXPECTED_FILE="$WINENET_SCRIPT_EXPECTED_DIR/$WINENET_NAME"
export WINENET_MSBUILD_TARGETS_FILE="$WINENET_DATA_DIR/msbuild_targets.xml"

#make script sourceable without all the internal things
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  return 0
fi

WINENET_MSBUILD_DEFAULT_TARGETS_IMPLEMENTATION="
<Project>
  <Target Name=\"WinenetAfterBuild\" AfterTargets=\"Build\" Condition=\"'\$(WinenetTargetPathFile)' != ''\">
    <WriteLinesToFile
      File=\"\$(WinenetTargetPathFile)\"
      Lines=\"\$(TargetDir)\$(AssemblyName).exe\"
      Overwrite=\"true\" />
  </Target>
</Project>
"
WINENET_TMP_DIR="$(mktemp -d -t winenet.XXXXXX)" || exit 1
trap 'rm -rf -- "$WINENET_TMP_DIR"' EXIT
DOTNET_INSTALL_SCRIPT_URL="https://dot.net/v1/dotnet-install.sh"
export WINEPREFIX="$WINENET_PREFIX"
#------HELPERS------#
get_user_bool() {
    local prompt="${1:-Continue?}"
    local response

    while true; do
        read -r -p "$prompt [Y/n]: " response
        response="${response:-Y}"
        case "$response" in
            [yY]|[yY][eE][sS])
                return 0
                ;;
            [nN]|[nN][oO])
                return 1
                ;;
            *)
                echo "Invalid response. Please enter 'y' or 'n'." >&2
                ;;
        esac
    done
}
run_checks() {
  if [[ ! (-d "$WINENET_PREFIX" && -d "$WINENET_DATA_DIR") ]]; then
    setup || return 1
  fi
  if [[ ! -f "$WINENET_MSBUILD_TARGETS_FILE" ]]; then
    printf "%s" "$WINENET_MSBUILD_DEFAULT_TARGETS_IMPLEMENTATION" > "$WINENET_MSBUILD_TARGETS_FILE" || return 1
  fi
}

#------SETUP------#
install_dotnet() {
  if get_user_bool "Would you like to install dotnet from '$DOTNET_INSTALL_SCRIPT_URL'?"; then
    printf "\n"
    source <(curl -fsSL -A "$WINENET_NAME" "$DOTNET_INSTALL_SCRIPT_URL") || return 1
  else
    printf "\n"
    return 1
  fi
}

ensure_dotnet() {
  if dotnet --info >/dev/null 2>&1; then
    return 0
  fi
  printf "Dotnet is not installed or missing from \$PATH\n"
  install_dotnet
}

get_dotnet_runtime_installer_urls() {
  local base_runtime="runtime"
  local asp_runtime="aspnetcore-runtime"
  local windowsdesktop_runtime="windowsdesktop"

  get_channel_manifest() {
    curl -fsSL \
      "https://builds.dotnet.microsoft.com/dotnet/release-metadata/$1/releases.json"
  }

  get_installer_url() {
    local manifest="$1"
    local version="$2"
    local section="$3"

    jq -r \
      --arg version "$version" \
      --arg section "$section" '
        .releases[]
        | select(."release-version" == $version)
        | .[$section].files[]?
        | select(.name | endswith("win-x64.exe"))
        | .url
      ' <<< "$manifest"
  }

  get_closest_desktop_version() {
    local manifest="$1"
    local requested_version="$2"
    local channel="${requested_version%.*}"

    jq -r \
      --arg channel "$channel" \
      --arg requested "$requested_version" '
        [
          .releases[]
          | ."release-version"
          | select(startswith($channel + "."))
        ]
        | if length == 0 then
            empty
          else
            sort_by(split(".") | map(tonumber))
            | . as $versions
            | (
                $versions
                | map(select(
                    (split(".") | map(tonumber))
                    <=
                    ($requested | split(".") | map(tonumber))
                  ))
                | last
              ) // $versions[0]
          end
      ' <<< "$manifest"
  }

  local runtime_map
  runtime_map="$(
    dotnet --list-runtimes |
    jq -Rn '
      [inputs
      | split(" ")
      | map(select(length > 0))
      | {family: .[0], version: .[1]}]
      | group_by(.family)
      | map({
        key: .[0].family,
        value: map(.version)
      })
      | from_entries
    '
  )" || return 1

  declare -A channel_map

  while IFS=$'\t' read -r family version; do
    local channel="${version%.*}"
    local section

    case "$family" in
      Microsoft.NETCore.App)
        section="$base_runtime"
        ;;
      Microsoft.AspNetCore.App)
        section="$asp_runtime"
        ;;
      *)
        continue
        ;;
    esac

    if [[ -z "${channel_map["$channel"]+x}" ]]; then
      channel_map["$channel"]="$(get_channel_manifest "$channel")" || return 1
    fi

    local manifest="${channel_map["$channel"]}"
    local installer_url

    installer_url="$(get_installer_url "$manifest" "$version" "$section")"

    if [[ -n "$installer_url" ]]; then
      printf '%s\n' "$installer_url"
    fi

    # .NET Core implies that Windows Desktop is useful in winenet.
    if [[ "$family" == "Microsoft.NETCore.App" ]]; then
      local desktop_version="$version"

      if [[ -z "$(get_installer_url "$manifest" "$desktop_version" "$windowsdesktop_runtime")" ]]; then
        desktop_version="$(
          get_closest_desktop_version "$manifest" "$version"
        )" || return 1
      fi

      installer_url="$(
        get_installer_url "$manifest" "$desktop_version" "$windowsdesktop_runtime"
      )"

      if [[ -n "$installer_url" ]]; then
        printf '%s\n' "$installer_url"
      fi
    fi
  done < <(
    jq -r '
      to_entries[]
      | .key as $family
      | .value[]
      | [$family, .]
      | @tsv
    ' <<< "$runtime_map"
  )
}

ensure_path() {
  if [[ ":$PATH:" != *":$WINENET_SCRIPT_EXPECTED_DIR:"* ]]; then
    printf "%s is not in your current \$PATH\n" "$WINENET_SCRIPT_EXPECTED_DIR"
    printf "Make sure to add %s to \$PATH to ensure %s's proper functionality and executability as %s is the script installation directory\n" "$WINENET_SCRIPT_EXPECTED_DIR" "$WINENET_NAME" "$WINENET_SCRIPT_EXPECTED_DIR"
    printf "Continuing installation\n"
  fi
}

create_wine_prefix() {
  mkdir -p "$WINENET_PREFIX" || return 1
  wineboot -u
}

setup() {
  printf "Setting up %s\n" "$WINENET_NAME"
  printf "Checking %s dependencies\n" "$WINENET_NAME"
  ensure_dotnet || return 1
  ensure_path
  
  printf "Dependencies checked, creating directories\n"
  
  mkdir -p "$WINENET_DATA_DIR" || return 1
  mkdir -p "$WINENET_PREFIX" || return 1
  
  printf "Setting up wine prefix\n"
  printf "Locating installed dotnet runtimes\n"
  local runtime_urls
  runtime_urls="$(get_dotnet_runtime_installer_urls)" || return 1
  local installers_dir="$WINENET_TMP_DIR/installers"
  mkdir -p "$installers_dir" || return 1
  local installer_paths=()
  local failed_installers=()
  printf "Downloading dotnet runtime installers\n"
  while IFS= read -r url; do
    local filename
    filename=$(basename "$url")
    local filepath="$installers_dir/$filename"
    printf "Downloading %s\n" "$filename"
    if curl -fsSL -o "$filepath" "$url"; then
      installer_paths+=("$filepath")
    else
      failed_installers+=("$url")
    fi
  done <<< "$runtime_urls"
  if ((${#failed_installers[@]} > 0)); then
    printf 'Failed to download:\n'
    for url in "${failed_installers[@]}"; do
      printf '  %s\n' "$url"
    done
  fi
  
  printf "Creating wine prefix\n"
  create_wine_prefix || return 1
  printf "Installing runtimes\n"
  local dotnet_installer_log_path="$WINENET_TMP_DIR/dotnet_installer.log"
  local wine_log_path="Z:${dotnet_installer_log_path//\//\\}"
  touch "$dotnet_installer_log_path"
  local installer
  for installer in "${installer_paths[@]}"; do
    tail -f "$dotnet_installer_log_path" &
    local tail_pid=$!

    printf "installing %s\n" "(basename '$installer')"
    wine "$installer" /quiet /norestart /log "$wine_log_path"
    local wine_status=$?

    kill "$tail_pid" 2>/dev/null
    wait "$tail_pid" 2>/dev/null

    ((wine_status == 0)) || return "$wine_status"
done
  
  printf "Writing MSBuild targets file\n"
  printf "%s\n" "$WINENET_MSBUILD_DEFAULT_TARGETS_IMPLEMENTATION" > "$WINENET_MSBUILD_TARGETS_FILE"
  
  printf "Installation done.\n"
}
#------RUN------#
resolve_dotnet_manifest_path() {
  local path="${1:-$PWD}"
  local manifest

  if [[ "$path" != /* ]]; then
    path="$PWD/$path"
  fi

  if [[ -f "$path" ]]; then
    case "$path" in
      *.csproj|*.fsproj|*.vbproj)
        realpath "$path"
        return 0
        ;;
      *)
        return 1
        ;;
    esac
  fi

  if [[ ! -d "$path" ]]; then
    return 1
  fi

  while true; do
    for manifest in "$path"/*.csproj "$path"/*.fsproj "$path"/*.vbproj; do
      if [[ -f "$manifest" ]]; then
        realpath "$manifest"
        return 0
      fi
    done

    [[ "$path" == "/" ]] && return 1
    path="$(dirname "$path")"
  done
}

run() {
  run_checks || return 1

  local path_arg
  local build_args=()
  local manifest_path
  local exe_path
  local exe_path_container_file_path="$WINENET_TMP_DIR/targetFile"
  
  path_arg=$1
  manifest_path="$(resolve_dotnet_manifest_path "$path_arg")" || return 1
  build_args=("${@:2}")
  
  dotnet build \
    "$manifest_path" \
    "${build_args[@]}" \
    "-p:CustomAfterMicrosoftCommonTargets=$WINENET_MSBUILD_TARGETS_FILE" \
    "-p:WinenetTargetPathFile=$exe_path_container_file_path" || return 1
  
  exe_path="$(<"$exe_path_container_file_path")"
  
  __msbuild-run "$exe_path"
}

__msbuild-run() {
  run_checks || return 1
  printf "Executing: %s\n" "$1"

  env \
    -u 'DOTNET_ROOT(x86)' \
    DOTNET_ROOT='C:\Program Files\dotnet' \
    DOTNET_ROOT_X64='C:\Program Files\dotnet' \
    wine "$1"
}

#------OTHER------#
print_help() {
    printf '%s\n' \
        "Usage: $WINENET_NAME <command> [options]" \
        "" \
        "Commands:" \
        "  setup             Set up or repair the Wine .NET environment" \
        "  run               Build and run a project through Wine" \
        "" \
        "Options:" \
        "  -h, --help        Show this help" \
        "  -v, --version     Show version" \
        "" \
        "Notes:" \
        "  This script can be sourced for of it's internal variables."
}

print_version() {
    printf '%s %s\n' "$WINENET_NAME" "$WINENET_VERSION"
}

#------DISPATCH------#
if [[ "$1" == "setup" || "$1" == "run" || "$1" == "__msbuild-run" ]]; then
  "$1" "${@:2}"
elif [[ "$1" == "--version" || "$1" == "-v" ]]; then
  print_version
elif [[ "$1" == "--help" || "$1" == "-h" ]]; then
  print_help
else
  printf "%s\n" "Unrecognized command" \
    "Use $0 --help to learn about $WINENET_NAME commands"
fi