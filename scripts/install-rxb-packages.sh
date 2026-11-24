#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
bundle_root="$(cd -- "$script_dir/.." && pwd)"
default_package_dir="$bundle_root/packages"
[[ -d "$bundle_root/dist" ]] && default_package_dir="$bundle_root/dist"
package_dir="${1:-$default_package_dir}"
[[ -d "$package_dir" ]] || {
  echo "install-rxb-packages: package directory does not exist: $package_dir" >&2
  exit 2
}
package_dir="$(cd -- "$package_dir" && pwd)"

if (( EUID != 0 )); then
  command -v sudo >/dev/null 2>&1 || {
    echo "install-rxb-packages: run as root or install sudo." >&2
    exit 1
  }
  script_path="$(readlink -f "$0")"
  exec sudo env \
    PACMAN_CONFIG="${PACMAN_CONFIG:-}" \
    RXB_PACMAN_NOCONFIRM="${RXB_PACMAN_NOCONFIRM:-0}" \
    "$script_path" "$package_dir"
fi

for command in pacman bsdtar awk sed head sort comm grep install mktemp stat vercmp; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "install-rxb-packages: required command is missing: $command" >&2
    exit 1
  }
done

# RXB_PACMAN_NOCONFIRM is a test-only escape hatch. It is accepted only inside
# the disposable Arch transaction harness, never on a normal CachyOS/Arch host.
if [[ "${RXB_PACMAN_NOCONFIRM:-0}" == 1 ]]; then
  marker=/run/rxb-install-test-disposable
  marker_uid=""
  marker_mode=""
  [[ -f /.dockerenv && ! -L /.dockerenv && -f "$marker" && ! -L "$marker" ]] || {
    echo "install-rxb-packages: RXB_PACMAN_NOCONFIRM is restricted to the disposable Arch transaction test." >&2
    exit 1
  }
  marker_uid="$(stat -c '%u' -- "$marker" 2>/dev/null || true)"
  marker_mode="$(stat -c '%a' -- "$marker" 2>/dev/null || true)"
  [[ "$marker_uid" == 0 && "$marker_mode" == 600 ]] || {
    echo "install-rxb-packages: disposable transaction marker is not root-owned mode 0600." >&2
    exit 1
  }
fi

safety_test="$script_dir/test-rxb-package-safety.sh"
[[ -x "$safety_test" ]] || {
  echo "install-rxb-packages: bundle is incomplete; missing scripts/test-rxb-package-safety.sh." >&2
  exit 1
}
bash "$safety_test" "$package_dir"

shopt -s nullglob
packages=("$package_dir"/*.pkg.tar.*)
(("${#packages[@]}" > 0)) || {
  echo "install-rxb-packages: no Arch package archives found in $package_dir" >&2
  exit 1
}

pacman_cmd=(pacman)
if [[ -n "${PACMAN_CONFIG:-}" ]]; then
  [[ -f "$PACMAN_CONFIG" ]] || {
    echo "install-rxb-packages: PACMAN_CONFIG does not exist: $PACMAN_CONFIG" >&2
    exit 1
  }
  pacman_cmd+=(--config "$PACMAN_CONFIG")
fi
pacman_exec() { "${pacman_cmd[@]}" "$@"; }
pacman_confirmed() {
  local operation="$1"
  shift
  if [[ "${RXB_PACMAN_NOCONFIRM:-0}" == 1 ]]; then
    pacman_exec "$operation" --noconfirm "$@"
  else
    pacman_exec "$operation" "$@"
  fi
}

declare -a package_names=()
declare -a external_dependency_specs=()
declare -a external_dependencies=()
declare -A local_provides=()
declare -A package_versions=()
declare -A seen_external_dependencies=()

for pkg in "${packages[@]}"; do
  metadata="$(bsdtar -xOf "$pkg" .PKGINFO)"
  name="$(sed -n 's/^pkgname = //p' <<<"$metadata" | head -n1)"
  [[ -n "$name" ]] || {
    echo "install-rxb-packages: cannot read package metadata from $pkg" >&2
    exit 1
  }
  [[ "$name" != *-debug ]] || {
    echo "install-rxb-packages: debug packages are not part of the RXB runtime set: $name" >&2
    exit 1
  }
  package_names+=("$name")
  package_versions["$name"]="$(sed -n 's/^pkgver = //p' <<<"$metadata" | head -n1)"
  local_provides["$name"]=1
  while IFS= read -r provided; do
    provided_name="${provided%%[<>=]*}"
    [[ -n "$provided_name" ]] && local_provides["$provided_name"]=1
  done < <(sed -n 's/^provides = //p' <<<"$metadata")
done

for required in ryoku-desktop-i3 ryoku-desktop ryogami; do
  [[ -n "${local_provides[$required]:-}" ]] || {
    echo "install-rxb-packages: package set is missing required local package/provider: $required" >&2
    exit 1
  }
done

# The manifest is the ownership boundary for safe upgrades and rollback.
manifest_dir="/var/lib/rxb"
manifest="$manifest_dir/installed-packages"
refuse_manifest() {
  echo "install-rxb-packages: refusing an unsafe RXB ownership manifest: $1" >&2
  exit 1
}
if [[ -L "$manifest_dir" ]]; then
  refuse_manifest "$manifest_dir is a symlink"
fi
if [[ -e "$manifest_dir" ]]; then
  [[ -d "$manifest_dir" && -O "$manifest_dir" ]] || refuse_manifest "$manifest_dir is not a root-owned directory"
  manifest_dir_mode="$(stat -c '%a' -- "$manifest_dir")"
  [[ "$manifest_dir_mode" =~ ^[0-7]{3,4}$ ]] || refuse_manifest "cannot read $manifest_dir permissions"
  (( (8#$manifest_dir_mode & 077) == 0 )) || refuse_manifest "$manifest_dir is accessible to group or other users"
fi
if [[ -L "$manifest" ]]; then
  refuse_manifest "$manifest is a symlink"
fi
declare -A owned_packages=()
if [[ -e "$manifest" ]]; then
  [[ -f "$manifest" && -O "$manifest" ]] || refuse_manifest "$manifest is not a root-owned regular file"
  manifest_mode="$(stat -c '%a' -- "$manifest")"
  [[ "$manifest_mode" =~ ^[0-7]{3,4}$ ]] || refuse_manifest "cannot read $manifest permissions"
  (( (8#$manifest_mode & 077) == 0 )) || refuse_manifest "$manifest is accessible to group or other users"
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    [[ "$name" =~ ^[a-z0-9][a-z0-9@._+-]*$ ]] || {
      echo "install-rxb-packages: invalid package name in existing manifest: $name" >&2
      exit 1
    }
    owned_packages["$name"]=1
  done < "$manifest"
fi

# Never replace an unrelated/manual Ryoku installation. Reinstallation and
# upgrades are allowed only for packages this installer previously recorded.
for name in "${package_names[@]}"; do
  if pacman_exec -Q "$name" >/dev/null 2>&1 && [[ -z "${owned_packages[$name]:-}" ]]; then
    echo "install-rxb-packages: refusing to overwrite pre-existing package '$name' not recorded as RXB-owned." >&2
    echo "Remove or back up that package deliberately, or use the RXB installer that originally installed it." >&2
    exit 1
  fi
done

# Refuse known replacements/conflicts before any dependency transaction. The
# preflight reports these too, but the installer must enforce the boundary.
for conflict in bibata-cursor-theme bibata-cursor-theme-bin gpk-bin tlp tuned-ppd; do
  if pacman_exec -Q "$conflict" >/dev/null 2>&1; then
    echo "install-rxb-packages: refusing because conflicting package '$conflict' is already installed." >&2
    echo "Resolve the conflict deliberately, then rerun the read-only host preflight." >&2
    exit 1
  fi
done

# Validate local Ryoku dependencies and collect only external dependency specs.
for pkg in "${packages[@]}"; do
  metadata="$(bsdtar -xOf "$pkg" .PKGINFO)"
  while IFS= read -r dependency; do
    dependency_name="${dependency%%[<>=]*}"
    case "$dependency_name" in
      ryoku*|ryogami*|gpk)
        [[ -n "${local_provides[$dependency_name]:-}" ]] || {
          echo "install-rxb-packages: missing local RXB dependency $dependency_name required by $pkg" >&2
          exit 1
        }
        continue
        ;;
    esac
    if [[ -n "${local_provides[$dependency_name]:-}" ]]; then
      continue
    fi
    if [[ -z "${seen_external_dependencies[$dependency]:-}" ]]; then
      seen_external_dependencies["$dependency"]=1
      external_dependency_specs+=("$dependency")
    fi
  done < <(sed -n 's/^depend = //p' <<<"$metadata")
done

write_manifest() {
  (("${#owned_packages[@]}" > 0)) || return 0
  [[ ! -L "$manifest_dir" && ! -L "$manifest" ]] || {
    echo "install-rxb-packages: ownership path became a symlink during installation." >&2
    return 1
  }
  if [[ -e "$manifest_dir" ]]; then
    [[ -d "$manifest_dir" && -O "$manifest_dir" ]] || {
      echo "install-rxb-packages: ownership directory changed ownership or type during installation." >&2
      return 1
    }
    dir_mode="$(stat -c '%a' -- "$manifest_dir")"
    [[ "$dir_mode" =~ ^[0-7]{3,4}$ ]] && (( (8#$dir_mode & 077) == 0 )) || {
      echo "install-rxb-packages: ownership directory permissions became unsafe during installation." >&2
      return 1
    }
  else
    install -d -m700 "$manifest_dir"
  fi
  if [[ -e "$manifest" ]]; then
    [[ -f "$manifest" && -O "$manifest" ]] || {
      echo "install-rxb-packages: ownership file changed ownership or type during installation." >&2
      return 1
    }
    file_mode="$(stat -c '%a' -- "$manifest")"
    [[ "$file_mode" =~ ^[0-7]{3,4}$ ]] && (( (8#$file_mode & 077) == 0 )) || {
      echo "install-rxb-packages: ownership file permissions became unsafe during installation." >&2
      return 1
    }
  fi
  manifest_tmp="$(mktemp)"
  printf '%s\n' "${!owned_packages[@]}" | sort -u > "$manifest_tmp"
  install -D -m600 "$manifest_tmp" "$manifest"
  rm -f -- "$manifest_tmp"
}

# Refuse every transaction while system upgrades are pending, even when all
# dependencies are already installed. RXB never updates the host kernel/GPU.
# pacman -Qu may return a nonzero status with an empty result on some
# configurations. Treat actual upgrade rows as pending updates; treat any
# other diagnostic output as an unsafe query failure.
pending_updates="$(pacman_exec -Qu 2>&1 || true)"
if [[ -n "$pending_updates" ]]; then
  if grep -Eq '^[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+->[[:space:]]+[^[:space:]]+' <<<"$pending_updates"; then
    echo "install-rxb-packages: pending system updates detected; refusing installation." >&2
    echo "Do not update the kernel or NVIDIA driver as part of RXB testing. Resolve updates only in a separately approved maintenance window, then rerun preflight." >&2
  else
    echo "install-rxb-packages: unable to verify pending system updates; refusing installation." >&2
  fi
  printf '%s\n' "$pending_updates" >&2
  exit 1
fi

before_file="$(mktemp)"
trap 'rm -f -- "$before_file"' EXIT
pacman_exec -Qq | sort -u > "$before_file"

if (("${#external_dependency_specs[@]}" > 0)); then
  mapfile -t unresolved_specs < <(pacman_exec -T "${external_dependency_specs[@]}" 2>/dev/null || true)
  if (("${#unresolved_specs[@]}" > 0)); then
    mapfile -t external_dependencies < <(
      printf '%s\n' "${unresolved_specs[@]}" |
        sed -E 's/[<>=].*$//' |
        sort -u
    )
    # Enforce Ryogami's Qt floor and preview the exact dependency transaction
    # before pacman is allowed to mutate the system.
    if current_qt="$(pacman_exec -Q qt6-base 2>/dev/null)"; then
      installed_qt="${current_qt#qt6-base }"
      if (( $(vercmp "$installed_qt" 6.12) < 0 )); then
        echo "install-rxb-packages: installed qt6-base $installed_qt is older than the required 6.12. Stop; resolve this in a separately approved maintenance window without changing the protected kernel/NVIDIA driver, then rerun preflight." >&2
        exit 1
      fi
    fi

    plan_file="$(mktemp)"
    if ! pacman_exec -Sp --needed --print-format '%n %v' "${external_dependencies[@]}" > "$plan_file"; then
      rm -f -- "$plan_file"
      echo "install-rxb-packages: could not resolve a read-only dependency transaction plan." >&2
      exit 1
    fi
    echo "Dependency transaction plan (new packages only):"
    if [[ -s "$plan_file" ]]; then cat "$plan_file"; else echo "  No external packages need to be installed."; fi
    while read -r planned_name planned_version; do
      [[ -n "$planned_name" && -n "$planned_version" ]] || continue
      installed_record="$(pacman_exec -Q "$planned_name" 2>/dev/null || true)"
      if [[ -n "$installed_record" ]]; then
        installed_version="${installed_record#"$planned_name "}"
        if [[ "$installed_version" != "$planned_version" ]]; then
          rm -f -- "$plan_file"
          echo "install-rxb-packages: dependency plan would upgrade installed package '$planned_name' from '$installed_version' to '$planned_version'." >&2
          echo "Refusing an implicit upgrade. Do not update the host as part of RXB testing; use a separately approved maintenance window or a disposable test environment." >&2
          exit 1
        fi
      fi
    done < "$plan_file"

    # Pre-record the planned new dependencies before pacman starts. If the
    # installer or pacman is interrupted mid-transaction, removal can inspect
    # which of these package names actually landed and remove only that subset.
    while read -r planned_name planned_version; do
      [[ -n "$planned_name" && -n "$planned_version" ]] || continue
      owned_packages["$planned_name"]=1
    done < "$plan_file"
    write_manifest
    rm -f -- "$plan_file"

    echo "Installing unsatisfied external dependencies from the reviewed plan."
    pacman_confirmed -S --needed "${external_dependencies[@]}"
  fi
  pacman_exec -T "${external_dependency_specs[@]}" >/dev/null || {
    echo "install-rxb-packages: external dependency requirements remain unsatisfied." >&2
    exit 1
  }
fi

# Record and mark newly installed external dependencies before the local
# package transaction. If that transaction fails, the rollback script can
# still remove the dependencies this installer introduced.
external_after_file="$(mktemp)"
pacman_exec -Qq | sort -u > "$external_after_file"
mapfile -t external_dependency_packages < <(comm -13 "$before_file" "$external_after_file")
rm -f -- "$external_after_file"
for name in "${external_dependency_packages[@]}"; do
  owned_packages["$name"]=1
done
if (("${#external_dependency_packages[@]}" > 0)); then
  write_manifest
  pacman_exec -D --asdeps "${external_dependency_packages[@]}"
fi

# Pre-record newly introduced local packages before pacman starts the
# transaction. If the installer is killed during the transaction, the remover
# can query which recorded packages actually landed and clean up that subset.
declare -a local_dependency_packages=()
for name in "${package_names[@]}"; do
  if ! grep -Fxq "$name" "$before_file"; then
    owned_packages["$name"]=1
    [[ "$name" == "ryoku-desktop-i3" ]] || local_dependency_packages+=("$name")
  fi
done
write_manifest

echo "Installing the complete RXB X11 package set from $package_dir."
pacman_confirmed -U "${packages[@]}"

if (("${#local_dependency_packages[@]}" > 0)); then
  pacman_exec -D --asdeps "${local_dependency_packages[@]}"
fi
pacman_exec -D --asexplicit ryoku-desktop-i3

for name in "${package_names[@]}"; do
  actual_version="$(pacman_exec -Q "$name" | awk '{print $2}')"
  [[ "$actual_version" == "${package_versions[$name]}" ]] || {
    echo "install-rxb-packages: package registration mismatch for $name: $actual_version" >&2
    echo "Newly installed packages remain recorded for rollback at $manifest." >&2
    exit 1
  }
done

echo
echo "RXB X11 package set installed."
echo "Session entry: Ryoku (X11 / i3)"
if [[ -f "$manifest" ]]; then
  echo "RXB-owned package record: $manifest"
else
  echo "No new packages were introduced; pre-existing packages were left outside the RXB removal record."
fi
echo "No SDDM configuration, Orbital theme, BSPWM session, Quickshell lockscreen, NVIDIA driver, kernel, or boot configuration was changed."
echo "Suspend/hibernate are intentionally disabled on X11 until secure lock-before-suspend support is validated."
