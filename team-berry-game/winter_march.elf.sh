#!/bin/sh
printf '\033c\033]0;%s\a' team-berry-game
base_path="$(dirname "$(realpath "$0")")"
"$base_path/winter_march.elf.x86_64" "$@"
