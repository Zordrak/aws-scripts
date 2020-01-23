#!/usr/bin/env bash

# Functions to help handle STS manipulation of IAM credentials from
# a shell console for AWS CLI, and other things - especially things
# that don't support IAM roles being specific in boto profile config
#
# When you use the mfa() function, we assume that you do not have your
# credentials defined with AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY
# variables in the environment. The credentials must be configured elsewhere
# in the boto search path such as ~/.aws/credentials or an EC2 Instance Profile
#
# The assumerole() function will overwrite the AWS_ACCESS_KEY_ID etc.
# environment variables, but does not wipe out what is already there
# to allow you to assume a role from an already MFA-authenticated session
#
# If you get in a muddle, use the unset-sts command and start again
# (or mfa, which issues unset-sts before doing anything)

# Function to clear current STS configuration.
#
# Use this to reset your session to your static AWS_PROFILE configuration
# removing any time-limited temporary credentials from your environment
function unset-sts() {
  unset AWS_ACCESS_KEY_ID;
  unset AWS_SECRET_ACCESS_KEY;
  unset AWS_SESSION_TOKEN;
  unset AWS_MFA_EXPIRY;
  unset AWS_SESSION_EXPIRY;
  unset AWS_ROLE;
}
export -f unset-sts;

# Authenticate with an MFA Token Code
function mfa() {

  # Remove any environment variables previously set by sts()
  unset-sts;

  # Get MFA Serial
  #
  # Assumes "iam list-mfa-devices" is permitted without MFA
  mfa_serial="$(aws iam list-mfa-devices --query 'MFADevices[*].SerialNumber' --output text)";
  if ! [ "${?}" -eq 0 ]; then
    echo "Failed to retrieve MFA serial number" >&2;
    return 1;
  fi;

  # Read the token from the console
  echo -n "MFA Token Code: ";
  read token_code;

  # Call STS to get the session credentials
  #
  # Assumes "sts get-session-token" is permitted without MFA
  session_tokens=($(aws sts get-session-token --token-code "${token_code}" --serial-number "${mfa_serial}" --output text));
  if ! [ "${?}" -eq 0 ]; then
    echo "STS MFA Request Failed" >&2;
    return 1;
  fi;

  # Set the environment credentials specifically for this command
  # and execute the command
  export AWS_ACCESS_KEY_ID="${session_tokens[1]}";
  export AWS_SECRET_ACCESS_KEY="${session_tokens[3]}";
  export AWS_SESSION_TOKEN="${session_tokens[4]}";
  export AWS_MFA_EXPIRY="${session_tokens[2]}";

  if [[ -n "${AWS_ACCESS_KEY_ID}" && -n "${AWS_SECRET_ACCESS_KEY}" && -n "${AWS_SESSION_TOKEN}" ]]; then
    echo "MFA Succeeded. With great power comes great responsibility...";
    return 0;
  else
    echo "MFA Failed" >&2;
    return 1;
  fi;
}
export -f mfa;

# Assume an IAM role
function assumerole(){

  declare -a session_tokens;

  local aws_account_id_current="$(aws sts get-caller-identity \
    --output text \
    --query Account)";

  local role="${1}";
  local aws_account_id_target="${2:-${aws_account_id_current}}";

  session_tokens=($(aws sts assume-role \
    --role-arn "arn:aws:iam::${aws_account_id_target}:role/${role}" \
    --role-session-name "${USER}-${HOSTNAME}-${TTYNR}" \
    --query Credentials \
    --output text; ));

  if ! [ "${?}" -eq 0 ]; then
    echo "STS Assume Role Request Failed" >&2;
    return 1;
  fi;

  # Set the environment credentials specifically for this command
  # and execute the command
  export AWS_ACCESS_KEY_ID="${session_tokens[0]}";
  export AWS_SECRET_ACCESS_KEY="${session_tokens[2]}";
  export AWS_SESSION_TOKEN="${session_tokens[3]}";
  export AWS_SESSION_EXPIRY="${session_tokens[1]}";

  if [[ \
       -n "${AWS_ACCESS_KEY_ID}"     \
    && -n "${AWS_SECRET_ACCESS_KEY}" \
    && -n "${AWS_SESSION_TOKEN}"     \
  ]]; then
    export AWS_ROLE="${role}"
    echo "Succeessfully assumed the ${role} role. With great power comes great responsibility...";
    return 0;
  else
    echo "STS Assume Role Failed" >&2;
    return 1;
  fi;
}

# Print current STS credentials status to the top right of the terminal
function aws_clock_print() {

  if [ -n "${AWS_ROLE}" ]; then
    # If we have assumed an IAM role, print the role and the remaining time before credentials expire

    output="[AWS_ROLE: ${AWS_ROLE}";

    expire_seconds="$(expr '(' $(date -d "${AWS_SESSION_EXPIRY}" +%s) - $(date +%s) ')' )";
    if [ "${expire_seconds}" -gt 0 ]; then
      output+=", SESSION TTL: $(date -u -d @"${expire_seconds}" +"%Hh %Mm %Ss")";
    else
      output+=", SESSION EXPIRED!";
    fi;
  else
    # If we haven't assumed an IAM role, print which AWS_PROFILE we are using (default if none set)

    output="[AWS_PROFILE: ";
    [ -n "${AWS_PROFILE}" ] && output+="${AWS_PROFILE}" || output+="default";

    if [ -n "${AWS_MFA_EXPIRY}" ]; then
      # If we are MFA authenticated, print the remaining time before credentials expire

      expire_seconds="$(expr '(' $(date -d "${AWS_MFA_EXPIRY}" +%s) - $(date +%s) ')' )";
      if [ "${expire_seconds}" -gt 0 ]; then
        output+=", MFA TTL: $(date -u -d @"${expire_seconds}" +"%Hh %Mm %Ss")";
      else
        output+=", MFA EXPIRED!";
      fi;
    fi;
  fi;

  output+="]";

  tput_x=$(( $(tput cols)-${#output} ));

  # If we have used tput to print longer output than we are about to print,
  # blank out the extra columns we previously wrote to
  if [ -n "${AWS_CLOCK_COLS_MIN}" ]; then
    if [ ${AWS_CLOCK_COLS_MIN} -le ${tput_x} ]; then
      export AWS_CLOCK_BLANKING=$(( ${tput_x}-${AWS_CLOCK_COLS_MIN} ));
    else
      export AWS_CLOCK_COLS_MIN="${tput_x}";
    fi;
  else
    export AWS_CLOCK_COLS_MIN="${tput_x}";
  fi;

  tput sc;

  if [[ -n "${AWS_CLOCK_BLANKING}" && "${AWS_CLOCK_BLANKING}" -gt 0 ]]; then
    tput cup 1 "${AWS_CLOCK_COLS_MIN}";
    printf %${AWS_CLOCK_BLANKING}s
  else
    tput cup 1 "${tput_x}";
  fi;

  tput bold;
  echo -n "${output}";
  tput rc;
}
export -f aws_clock_print

export PROMPT_COMMAND="aws_clock_print; ${PROMPT_COMMAND}";
