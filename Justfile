just := just_executable()

# Check the syntax of all Justfiles in the repository
check:
    #!/usr/bin/bash
    find . -type f -name "*.just" | while read -r file; do
      echo "Checking syntax: $file"
      {{ just }} --fmt --check -f $file
    done
    echo "Checking syntax: Justfile"
    {{ just }} --fmt --check -f Justfile

# Fix the Just formatting
fix:
    #!/usr/bin/bash
    find . -type f -name "*.just" | while read -r file; do
      echo "Fixing syntax: $file"
      {{ just }} --fmt -f $file
    done
    echo "Fixing syntax: Justfile"
    {{ just }} --fmt -f Justfile || { exit 1; }

# Runs shell check on all Bash scripts
shell-lint dir="system_files":
    #!/usr/bin/env bash
    set -eoux pipefail
    # Check if shellcheck is installed
    if ! command -v shellcheck &> /dev/null; then
        echo "shellcheck could not be found. Please install it."
        exit 1
    fi
    # Run shellcheck on all Bash scripts
    /usr/bin/find {{ dir }} -type d -name ".*" -prune -o -type f \( -name "*.sh" -o -exec sh -c 'head -n 1 "$1" | grep -qE "^#!(.*/bin/(bash|sh|zsh)|/usr/bin/env (bash|sh|zsh))"' _ {} \; \) -exec shellcheck {} +

# Runs shfmt on all Bash scripts
shell-format:
    #!/usr/bin/env bash
    set -eoux pipefail
    # Check if shfmt is installed
    if ! command -v shfmt &> /dev/null; then
        echo "shfmt could not be found. Please install it."
        exit 1
    fi
    # Run shfmt on all Bash scripts
    /usr/bin/find . -iname "*.sh" -type f -exec shfmt --write "{}" ';'

# Validate Brewfiles
brew-lint dir="system_files/shared/usr/share/ublue-os/homebrew":
    #!/usr/bin/env bash
    set -uo pipefail

    status_file="$(mktemp)"
    : > "$status_file"

    # Brewfiles in this repo are named like "cli.Brewfile", not literally "Brewfile".
    while IFS= read -r -d '' brewfile; do
      echo "::group:: ===$(basename "$brewfile")==="

      # Single top-to-bottom pass: taps are declared before they're used, so we
      # tap + trust each one as we reach it, then validate brew/cask entries as
      # they come (Homebrew >=6 needs a tap added and trusted before it will
      # resolve any formula/cask from it; there's no auto-tap).
      while IFS= read -r line; do
        if [[ "$line" =~ ^tap[[:space:]]+\"([^\"]+)\"(,[[:space:]]*\"([^\"]+)\")? ]]; then
          name="${BASH_REMATCH[1]}"
          remote="${BASH_REMATCH[3]}"
          brew tap "$name" ${remote:+"$remote"} > /dev/null 2>&1 || true
          brew trust --tap "$name" > /dev/null 2>&1 || true

          # `brew info` has no `--tap` flag; taps are checked with `tap-info`.
          if brew tap-info "$name" &>/dev/null; then
            echo "✓ tap \"$name\" is valid"
          else
            echo "✗ tap \"$name\" is invalid ($brewfile)"
            echo "FAIL" >> "$status_file"
          fi
        elif [[ "$line" =~ ^(brew|cask)[[:space:]]+\"([^\"]+)\" ]]; then
          type="${BASH_REMATCH[1]}"
          name="${BASH_REMATCH[2]}"

          # The Brewfile DSL keyword is "brew", but `brew info` expects "--formula".
          flag="$type"
          [[ "$type" == "brew" ]] && flag="formula"

          if brew info --"$flag" "$name" &>/dev/null; then
            echo "✓ $type \"$name\" is valid"
          else
            echo "✗ $type \"$name\" is invalid or missing tap ($brewfile)"
            echo "FAIL" >> "$status_file"
          fi
        fi
      done < "$brewfile"

      echo "::endgroup::"
    done < <(find "{{ dir }}" -iname '*.Brewfile' -print0)

    if grep -q FAIL "$status_file"; then
      echo "Validation complete. Some Brewfiles FAILED."
      rm -f "$status_file"
      exit 1
    fi

    echo "Validation complete. All Brewfiles passed."
    rm -f "$status_file"
