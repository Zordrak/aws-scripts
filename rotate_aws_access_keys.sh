#!/usr/bin/env bash

##
# rotate_aws_access_keys.sh
#
# Used to rotate AWS Access Keys in AWS accounts
# that are configured as profiles in ~/.aws
#
# Usage:
#   Rotate access keys for all profiles
#   present in the ~/.aws/credentials file:
#   $ ./rotate_aws_access_keys.sh
#
#   Rotate access keys for specific profiles by name:
#   $ ./rotate_aws_access_keys.sh profile1 [profile2] [profile3]
#
# Requires: jq
#
# Requires: A function called mfa that clears all
# current AWS IAM session environment variables
# and then prompts for an MFA token at the command line,
# setting new AWS IAM session environment variables and
# returning a non-zero code on failure.
# This is available in the .aws_helper.sh script by
# Mike Peachey and other people have written equivalents.
#
# Makes use of the bashlog library:
#   https://github.com/Zordrak/bashlog
# provides all of the logging options and features therein.
##

set -uo pipefail;

function _log_exception() {
  (
    BASHLOG_FILE=0;
    BASHLOG_JSON=0;
    BASHLOG_SYSLOG=0;

    log 'error' "Logging Exception: ${@}";
  );
}

function log() {
  local date_format="${BASHLOG_DATE_FORMAT:-+%F %T}";
  local date="$(date "${date_format}")";
  local date_s="$(date "+%s")";

  local file="${BASHLOG_FILE:-0}";
  local file_path="${BASHLOG_FILE_PATH:-/tmp/$(basename "${0}").log}";

  local json="${BASHLOG_JSON:-0}";
  local json_path="${BASHLOG_JSON_PATH:-/tmp/$(basename "${0}").log.json}";

  local syslog="${BASHLOG_SYSLOG:-0}";
  local tag="${BASHLOG_SYSLOG_TAG:-$(basename "${0}")}";
  local facility="${BASHLOG_SYSLOG_FACILITY:-local0}";
  local pid="${$}";

  local level="${1}";
  local upper="$(echo "${level}" | awk '{print toupper($0)}')";
  local debug_level="${DEBUG:-0}";

  shift 1;

  local line="${@}";

  # RFC 5424
  #
  # Numerical         Severity
  #   Code
  #
  #    0       Emergency: system is unusable
  #    1       Alert: action must be taken immediately
  #    2       Critical: critical conditions
  #    3       Error: error conditions
  #    4       Warning: warning conditions
  #    5       Notice: normal but significant condition
  #    6       Informational: informational messages
  #    7       Debug: debug-level messages

  local severities_DEBUG=7;
  local severities_INFO=6;
  local severities_NOTICE=5; # Unused
  local severities_WARN=4;
  local severities_ERROR=3;
  local severities_CRIT=2;   # Unused
  local severities_ALERT=1;  # Unused
  local severities_EMERG=0;  # Unused

  local severity_var="severities_${upper}";
  local severity="${!severity_var:-3}"

  if [ "${debug_level}" -gt 0 ] || [ "${severity}" -lt 7 ]; then

    if [ "${syslog}" -eq 1 ]; then
      local syslog_line="${upper}: ${line}";

      logger \
        --id="${pid}" \
        -t "${tag}" \
        -p "${facility}.${severity}" \
        "${syslog_line}" \
        || _log_exception "logger --id=\"${pid}\" -t \"${tag}\" -p \"${facility}.${severity}\" \"${syslog_line}\"";
    fi;

    if [ "${file}" -eq 1 ]; then
      local file_line="${date} [${upper}] ${line}";
      echo -e "${file_line}" >> "${file_path}" \
        || _log_exception "echo -e \"${file_line}\" >> \"${file_path}\"";
    fi;

    if [ "${json}" -eq 1 ]; then
      local json_line="$(printf '{"timestamp":"%s","level":"%s","message":"%s"}' "${date_s}" "${level}" "${line}")";
      echo -e "${json_line}" >> "${json_path}" \
        || _log_exception "echo -e \"${json_line}\" >> \"${json_path}\"";
    fi;

  fi;

  local colours_DEBUG='\033[34m'  # Blue
  local colours_INFO='\033[32m'   # Green
  local colours_NOTICE=''         # Unused
  local colours_WARN='\033[33m'   # Yellow
  local colours_ERROR='\033[31m'  # Red
  local colours_CRIT=''           # Unused
  local colours_ALERT=''          # Unused
  local colours_EMERG=''          # Unused
  local colours_DEFAULT='\033[0m' # Default

  local norm="${colours_DEFAULT}";
  local colour_var="colours_${upper}";
  local colour="${!colour_var:-\033[31m}";

  local std_line="${colour}${date} [${upper}] ${line}${norm}";

  # Standard Output (Pretty)
  case "${level}" in
    'info'|'warn')
      echo -e "${std_line}";
      ;;
    'debug')
      if [ "${debug_level}" -gt 0 ]; then
        echo -e "${std_line}";
      fi;
      ;;
    'error')
      echo -e "${std_line}" >&2;
      if [ "${debug_level}" -gt 0 ]; then
        echo -e "Here's a shell to debug with. 'exit 0' to continue. Other exit codes will abort - parent shell will terminate.";
        bash || exit "${?}";
      else
        exit 1;
      fi;
      ;;
    *)
      log 'error' "Undefined log level trying to log: ${@}";
      ;;
  esac
}

declare prev_cmd="null";
declare this_cmd="null";
trap 'prev_cmd=$this_cmd; this_cmd=$BASH_COMMAND' DEBUG \
  && log debug 'DEBUG trap set' \
  || log error 'DEBUG trap failed to set';

# This is an option if you want to log every single command executed,
# but it will significantly impact script performance and unit tests will fail

#trap 'prev_cmd=$this_cmd; this_cmd=$BASH_COMMAND; log debug $this_cmd' DEBUG \
#  && log debug 'DEBUG trap set' \
#  || log error 'DEBUG trap failed to set';

jq -r . <<<"" 2>&1 1>/dev/null || log 'error' 'jq not present and usable';

[ -r ~/.aws/credentials ] || log 'error' '~/.aws/credentials not readable';
[ -w ~/.aws/credentials ] || log 'error' '~/.aws/credentials not writable';

declare -a profiles;

if [ "${1:-""}" == "" ]; then
  log 'info' 'No profile(s) specified. Iterating all profiles in ~/.aws/credentials';
  profiles=($(\grep -oP '\[.*?\]' ~/.aws/credentials | sed 's/[][]//g'));
else
  profiles=("${@}");
fi;

declare -a succeeded=();
declare -a skipped=();

for profile in ${profiles[@]}; do

  echo -n "Replace the Access Key for profile ${profile}? (Y/n): ";
  read line;
  case "${line}" in
    y|Y|'')
      ;;
    *)
      log 'info' "[${profile}] Skipping profile by request";
      skipped+=("${profile}");
      continue;
      ;;
  esac;

  export AWS_PROFILE=${profile};
  log 'info' "[${profile}] Initiating MFA session";
  mfa || { log 'warn' "[${profile}] MFA Failure. Skipping." && skipped+=("${profile}") && continue; };
  declare existing_keys="$(aws iam list-access-keys --o json)" \
    || { log 'warn' "[${profile}] Couldn't retrieve access keys. Permission failure? Skipping." && skipped+=("${profile}") && continue; };
  declare num_keys="$(jq -r '.AccessKeyMetadata | length' <<<"${existing_keys}")";
  case "${num_keys}" in
    0)
      log 'warn' "[${profile}] No existing key - how did we even get here? - Skipping.";
      skipped+=("${profile}");
      continue;
      ;;
    1)
      existing_key_id="$(jq -r '.AccessKeyMetadata[0].AccessKeyId' <<<"${existing_keys}")";
      log 'info' "[${profile}] One existing key found to replace: ${existing_key_id}";
      ;;
    2)
      log 'warn' "[${profile}] Two keys already present. We can't create a third, so this automated process won't work - Skipping.";
      skipped+=("${profile}");
      continue;
      ;;
  esac;
 
  declare new_key="$(aws iam create-access-key --o json)" \
    || { log 'warn' "[${profile}] Couldn't create access key. Permission failure? Skipping." && skipped+=("${profile}") && continue; };
  declare new_a_k_id=$(jq -r .AccessKey.AccessKeyId <<<"${new_key}");
  declare new_s_a_k=$(jq -r .AccessKey.SecretAccessKey <<<"${new_key}");
  declare a_k_id_to_replace="$(aws configure get aws_access_key_id)" \
    || { log 'warn' "[${profile}] Couldn't get existing AWS Access Key ID via 'aws configure'. Skipping." && skipped+=("${profile}") && continue; };

  if [ "${a_k_id_to_replace}" != "${existing_key_id}" ]; then
    log 'error' "[${profile}] The key in ~/.aws/credentials for this profile isn't the same as the one in IAM. Terminating so you can handle this manually. You will now have both old and new keys configured in AWS and the old one in your ~/.aws/credentials file.";
    continue;
  fi;

  log 'info' "[${profile}] Replacing key ${a_k_id_to_replace} with ${new_a_k_id} in ~/.aws/credentials";
  aws configure set aws_access_key_id "${new_a_k_id}" \
    || { log 'warn' "[${profile}] Couldn't set new AWS Access Key ID via 'aws configure'. Skipping." && skipped+=("${profile}") && continue; };
  aws configure set aws_secret_access_key "${new_s_a_k}" \
    || log 'error' "[${profile}] Couldn't set new AWS Secret Access Key via 'aws configure'. Terminating so you can handle this manually. You will now have a non matching Key ID and Secret Key in ~/.aws/credentials for this profile.";

  # This is feels safer, but it's unnecessary. We can delete the key with the existing MFA session.
  # log 'info' "[${profile}] Waiting 15 seconds for IAM eventual consistency (you'll need to wait for a new MFA token anyway)...";
  # sleep 15;
  # log 'info' "[${profile}] Initiating MFA session with new key, so we can delete the old one";
  # mfa || log 'error' "[${profile}] MFA failure after replacing the key. Terminating so you can handle this manually. You will now have both old and new keys configured in AWS and the new one in your ~/.aws/credentials file.";

  log 'info' "[${profile}] Deleting access key ${existing_key_id}";
  aws iam delete-access-key --access-key-id "${existing_key_id}" \
    || log 'error' "[${profile}] Couldn't delete the old Access Key (${existing_key_id}). Terminating so you can handle this manually.";

  log 'info' "[${profile}] Successfully rotated Access Key";
  succeeded+=("${profile}");
done;

log 'info' "All profiles finished.";

[[ ${#skipped[@]} -gt 0 ]] && log 'warn' "Profiles skipped: ${skipped[@]}";
[[ ${#succeeded[@]} -gt 0 ]] && log 'info' "Profiles succeeded: ${succeeded[@]}";

exit 0;
