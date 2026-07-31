#!/usr/bin/env bash
# cmd-wrapper-helpers.sh — source this file; do not execute directly.
#
# Provides CMD — generic CLI wrapper for az, aws, gcloud, databricks,
# mysql, psql, sqlcmd, oci, etc.
#
# shellcheck source=cmd-wrapper-helpers.sh
# source "$(dirname "${BASH_SOURCE[0]}")/cmd-wrapper-helpers.sh"
# 
# See shell-cmd-wrapper skill for full documentation.
(return 0 2>/dev/null) || { echo "error: source this file, do not execute it" >&2; exit 1; }

# ---------------------------------------------------------------------------
# CMD — generic CLI wrapper. Derives /tmp/<binary>_stdout[_<suffix>].<PID>
#       from basename $1, prints the command (with masking), captures stdout
#       and stderr to temp files, and handles errors inline.
#
# Caller-settable vars (all optional):
#   CMD_EXIT_ON_ERROR  — PRINT_EXIT | PRINT_RETURN | RETURN_1_STDOUT_EMPTY | (empty=continue)
#   CMD_TIMEOUT        — seconds; wraps call in `timeout`; 0 or unset = no timeout
#   CMD_OUT_SUFFIX     — appended to temp file names to disambiguate sequential calls
#   CMD_STDOUT         — override the default stdout temp file path
#   CMD_STDERR         — override the default stderr temp file path
#   CMD_MASK_SECRETS   — bash ARRAY of secret values replaced with *** in log output
#                        (must be set as a standalone statement before CMD — NOT as a
#                        command prefix, because bash passes array prefixes as a scalar
#                        string "(value)" including literal parens, which never matches)
#
# Temp file paths (auto-constructed; read output from here — never use $())
#   /tmp/<binary>_stdout[_<suffix>].<PID>   e.g. /tmp/az_stdout.$$
#   /tmp/<binary>_stderr[_<suffix>].<PID>   e.g. /tmp/az_stderr.$$
# ---------------------------------------------------------------------------
CMD() {
  local _cli
  _cli=$(basename "$1")
  local _suffix="${CMD_OUT_SUFFIX:+_${CMD_OUT_SUFFIX}}"
  local CMD_EXIT_ON_ERROR="${CMD_EXIT_ON_ERROR:-}"
  local CMD_STDOUT="${CMD_STDOUT:-/tmp/${_cli}_stdout${_suffix}.$$}"
  local CMD_STDERR="${CMD_STDERR:-/tmp/${_cli}_stderr${_suffix}.$$}"
  local CMD_TIMEOUT="${CMD_TIMEOUT:-0}"
  local RC

  # Snapshot CMD_MASK_SECRETS into a local and immediately clear the global so
  # callers do not need to reset it between CMD invocations.
  local _mask=("${CMD_MASK_SECRETS[@]+"${CMD_MASK_SECRETS[@]}"}")
  CMD_MASK_SECRETS=()

  local PWMASK="$*"
  local _secret _escaped
  for _secret in "${_mask[@]+"${_mask[@]}"}"; do
    if [[ -n "$_secret" ]]; then
      _escaped="$_secret"
      _escaped="${_escaped//\\/\\\\}"   # backslash first (order matters)
      _escaped="${_escaped//\*/\\*}"
      _escaped="${_escaped//\?/\\?}"
      _escaped="${_escaped//\[/\\[}"
      PWMASK="${PWMASK//${_escaped}/***}"
    fi
  done
  if (( CMD_TIMEOUT > 0 )); then
    echo -n "  + [timeout=${CMD_TIMEOUT}s] ${PWMASK}"
    timeout "$CMD_TIMEOUT" "$@" >"${CMD_STDOUT}" 2>"${CMD_STDERR}"
  else
    echo -n "  + ${PWMASK}"
    "$@" >"${CMD_STDOUT}" 2>"${CMD_STDERR}"
  fi
  RC=$?

  if [[ "$RC" != "0" ]]; then
    if [[ "${CMD_EXIT_ON_ERROR}" == "PRINT_RETURN" ]]; then
      echo " failed (RC=${RC})" >&2
      [[ -s "${CMD_STDOUT}" ]] && cat "${CMD_STDOUT}" >&2
      [[ -s "${CMD_STDERR}" ]] && cat "${CMD_STDERR}" >&2
      return "$RC"
    elif [[ "${CMD_EXIT_ON_ERROR}" == "PRINT_EXIT" ]]; then
      echo " failed (RC=${RC})" >&2
      [[ -s "${CMD_STDOUT}" ]] && cat "${CMD_STDOUT}" >&2
      [[ -s "${CMD_STDERR}" ]] && cat "${CMD_STDERR}" >&2
      kill -INT $$
    else
      echo " failed (RC=${RC}) — continuing" >&2
      return "$RC"
    fi
  else
    echo ""   # newline after the echoed command on success
    if [[ "${CMD_EXIT_ON_ERROR}" == "RETURN_1_STDOUT_EMPTY" && ! -s "${CMD_STDOUT}" ]]; then
      return 1
    fi
  fi
  return 0
}
export -f CMD
