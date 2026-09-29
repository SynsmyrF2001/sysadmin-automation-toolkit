#!/usr/bin/env bash
#
# lib/config.sh
#
# Shared config-loading helper for this repo's Bash scripts -- the same
# local-then-example fallback chain as powershell/modules/Config.psm1's
# Get-ToolkitConfig, extracted now that a second script (backup.sh)
# needs the identical logic rotate-logs.sh already had inline.
#
# Usage: source this file, then call:
#   load_toolkit_config "/path/to/config/dir" "logrotate"
# which sources <dir>/logrotate.conf.local if present, else
# <dir>/logrotate.conf.example, else returns non-zero.
#
# Sourcing happens INSIDE this function, but the variables it sets
# still end up visible to whatever script called load_toolkit_config --
# because none of them are declared `local` in the config file itself,
# they're plain global assignments, and a sourced file's assignments
# become part of whatever scope did the sourcing. Same "global by
# default" behavior flagged in logging.sh, just working in this
# function's favor here instead of being a hazard.

load_toolkit_config() {
    local config_dir="$1"
    local base_name="$2"

    local local_path="$config_dir/${base_name}.conf.local"
    local example_path="$config_dir/${base_name}.conf.example"

    if [ -f "$local_path" ]; then
        source "$local_path"
    elif [ -f "$example_path" ]; then
        source "$example_path"
    else
        echo "No config found at $local_path or $example_path" >&2
        return 1
    fi
}
