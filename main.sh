#!/bin/bash

# Setup

TELEGRAM_KEY=""
TELEGRAM_CHAT_ID=""
UPDATE_REQUESTS=60
APPROVAL_TEXT="Please approve deployment"
APPROVAL_BUTTON="Approve"
REJECT_BUTTON="Reject"
APPROVED_TEXT="Approved!"
REJECTED_TEXT="Rejected!"
TIMEOUT_TEXT="Timeout!"
GITHUB_USERNAME_TO_TELEGRAM_USER_ID=""
ALLOWED_APPROVERS=""
EXCLUDE_WORKFLOW_INITIATOR_AS_APPROVER="false"
SUPER_APPROVERS=""
APPROVAL_THRESHOLD=1
REJECT_REASON_REQUIRED="false"

# Define long options
LONGOPTS=TELEGRAM_KEY:,TELEGRAM_CHAT_ID:,UPDATE_REQUESTS:,APPROVAL_TEXT:,APPROVAL_BUTTON:,REJECT_BUTTON:,APPROVED_TEXT:,REJECTED_TEXT:,TIMEOUT_TEXT:,GITHUB_USERNAME_TO_TELEGRAM_USER_ID:,ALLOWED_APPROVERS:,EXCLUDE_WORKFLOW_INITIATOR_AS_APPROVER:,SUPER_APPROVERS:,APPROVAL_THRESHOLD:,REJECT_REASON_REQUIRED:

VALID_ARGS=$(getopt --longoptions $LONGOPTS -- "$@")
if [[ $? -ne 0 ]]; then
    exit 1;
fi

# Extract the options and arguments
while true; do
  if [[ $1 == '' ]]; then
    break;
  fi
  if [[ $1 == ' ' ]]; then
    break;
  fi
  echo "$1 => $2"
  case "$1" in
    --TELEGRAM_KEY)
      TELEGRAM_KEY="$2"
      shift 2
      ;;
    --TELEGRAM_CHAT_ID)
      TELEGRAM_CHAT_ID="$2"
      shift 2
      ;;
    --UPDATE_REQUESTS)
      UPDATE_REQUESTS="$2"
      shift 2
      ;;
    --APPROVAL_TEXT)
      APPROVAL_TEXT="$2"
      shift 2
      ;;
    --APPROVAL_BUTTON)
      APPROVAL_BUTTON="$2"
      shift 2
      ;;
    --REJECT_BUTTON)
      REJECT_BUTTON="$2"
      shift 2
      ;;
    --APPROVED_TEXT)
      APPROVED_TEXT="$2"
      shift 2
      ;;
    --REJECTED_TEXT)
      REJECTED_TEXT="$2"
      shift 2
      ;;
    --TIMEOUT_TEXT)
      TIMEOUT_TEXT="$2"
      shift 2
      ;;
    --GITHUB_USERNAME_TO_TELEGRAM_USER_ID)
      GITHUB_USERNAME_TO_TELEGRAM_USER_ID="$2"
      shift 2
      ;;
    --ALLOWED_APPROVERS)
      ALLOWED_APPROVERS="$2"
      shift 2
      ;;
    --EXCLUDE_WORKFLOW_INITIATOR_AS_APPROVER)
      EXCLUDE_WORKFLOW_INITIATOR_AS_APPROVER="$2"
      shift 2
      ;;
    --SUPER_APPROVERS)
      SUPER_APPROVERS="$2"
      shift 2
      ;;
    --APPROVAL_THRESHOLD)
      APPROVAL_THRESHOLD="$2"
      shift 2
      ;;
    --REJECT_REASON_REQUIRED)
      REJECT_REASON_REQUIRED="$2"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    *)
      break
      ;;
  esac
done
if [ -z "$TELEGRAM_KEY" ]; then
  echo "TELEGRAM_KEY is required"
  exit 1
fi

if [ -z "$TELEGRAM_CHAT_ID" ]; then
  echo "TELEGRAM_CHAT_ID is required"
  exit 1
fi

if ! [[ "$APPROVAL_THRESHOLD" =~ ^[0-9]+$ ]] || [ "$APPROVAL_THRESHOLD" -lt 1 ]; then
  APPROVAL_THRESHOLD=1
fi

# Logic

normalize_list() {
  echo "$1" | tr ',;' '\n' | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | awk 'NF'
}

is_in_list() {
  local item="$1"
  local list="$2"

  if [ -z "$list" ]; then
    return 1
  fi

  while IFS= read -r entry; do
    if [ "$entry" = "$item" ]; then
      return 0
    fi
  done < <(normalize_list "$list")

  return 1
}

get_mapping_value() {
  local key="$1"
  local mapping="$2"

  while IFS= read -r entry; do
    local entry_trimmed
    entry_trimmed=$(echo "$entry" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    local map_key="${entry_trimmed%%:*}"
    local map_value="${entry_trimmed#*:}"
    map_key=$(echo "$map_key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    map_value=$(echo "$map_value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [ "$map_key" = "$key" ] && [ -n "$map_value" ] && [ "$map_value" != "$entry_trimmed" ]; then
      echo "$map_value"
      return 0
    fi
  done < <(normalize_list "$mapping")

  return 1
}

get_github_user_by_telegram_id() {
  local telegram_id="$1"
  local mapping="$2"

  while IFS= read -r entry; do
    local entry_trimmed
    entry_trimmed=$(echo "$entry" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    local map_key="${entry_trimmed%%:*}"
    local map_value="${entry_trimmed#*:}"
    map_key=$(echo "$map_key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    map_value=$(echo "$map_value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [ "$map_value" = "$telegram_id" ] && [ -n "$map_key" ] && [ "$map_value" != "$entry_trimmed" ]; then
      echo "$map_key"
      return 0
    fi
  done < <(normalize_list "$mapping")

  return 1
}

is_truthy() {
  case "$(echo "$1" | tr '[:upper:]' '[:lower:]')" in
    true|1|yes|y) return 0 ;;
    *) return 1 ;;
  esac
}

is_user_allowed() {
  local telegram_id="$1"
  local telegram_username="$2"

  if [ -z "$ALLOWED_APPROVERS" ]; then
    return 0
  fi

  local github_user
  github_user=$(get_github_user_by_telegram_id "$telegram_id" "$GITHUB_USERNAME_TO_TELEGRAM_USER_ID")

  if [ -z "$github_user" ]; then
    return 1
  fi

  if is_in_list "$github_user" "$ALLOWED_APPROVERS" || is_in_list "$github_user" "$SUPER_APPROVERS"; then
    return 0
  fi

  return 1
}

is_user_excluded() {
  local telegram_id="$1"
  local github_user="$2"

  if ! is_truthy "$EXCLUDE_WORKFLOW_INITIATOR_AS_APPROVER"; then
    return 1
  fi

  if [ -z "$GITHUB_ACTOR" ] || [ -z "$github_user" ]; then
    return 1
  fi

  if is_in_list "$github_user" "$SUPER_APPROVERS"; then
    return 1
  fi

  if [ "$github_user" = "$GITHUB_ACTOR" ]; then
    return 0
  fi

  return 1
}

generate_random_string() {
  # Количество символов в строке
  local STRING_LENGTH=12

  # Символы, из которых будет сгенерирована строка
  local CHAR_SET="abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

  # Переменная для хранения итоговой строки
  local RANDOM_STRING=""

  # Используйте цикл for для выбора случайных символов из CHAR_SET
  for i in $(seq 1 $STRING_LENGTH); do
    # Выбор случайного индекса от 0 до ${#CHAR_SET}-1
    local INDEX=$((RANDOM % ${#CHAR_SET}))

    # Добавление случайного символа из CHAR_SET к RANDOM_STRING
    RANDOM_STRING="${RANDOM_STRING}${CHAR_SET:$INDEX:1}"
  done

  # Вывод сгенерированной строки
  echo "$RANDOM_STRING"
}

SESSION_ID=$(generate_random_string)
echo $"Session ID: $SESSION_ID"

MESSAGE_ID=""

sendMessage() {
  local SENT=$(curl -s --location --request POST "https://api.telegram.org/bot$TELEGRAM_KEY/sendMessage" \
    --header 'Content-Type: application/json' \
    --data '{
        "chat_id": "'"$TELEGRAM_CHAT_ID"'",
        "text": "'"$APPROVAL_TEXT"'",
        "reply_markup": {
            "inline_keyboard": [
                [
                    {"text": "'"$APPROVAL_BUTTON"'", "callback_data": "a:'"$SESSION_ID"'"},
                    {"text": "'"$REJECT_BUTTON"'", "callback_data": "r:'"$SESSION_ID"'"}
                ]
            ]
        }
    }')

  # get message id without jq
  MESSAGE_ID=$(echo $SENT | awk -F '"message_id":' '{print $2}' | awk -F ',' '{print $1}')
  echo "Message ID: $MESSAGE_ID"
}

sendRejectReasonRequest() {
  local approver_name="$1"

  curl -s --location --request POST "https://api.telegram.org/bot$TELEGRAM_KEY/sendMessage" \
    --header 'Content-Type: application/json' \
    --data '{
        "chat_id": "'"$TELEGRAM_CHAT_ID"'",
        "text": "Please provide a rejection reason'"$approver_name"'",
        "reply_markup": {"force_reply": true}
    }'
}

parse_latest_update() {
  local updates="$1"

  echo "$updates" | python3 - <<'PY'
import json
import sys

data = json.load(sys.stdin)
result = data.get("result") or []
if not result:
    print("")
    sys.exit(0)

item = result[-1]
if "callback_query" in item:
    cq = item["callback_query"]
    from_user = cq.get("from", {})
    data_value = cq.get("data", "")
    from_id = from_user.get("id", "")
    username = from_user.get("username", "")
    print(f"callback|{data_value}|{from_id}|{username}|")
elif "message" in item:
    msg = item["message"]
    from_user = msg.get("from", {})
    text = msg.get("text", "")
    from_id = from_user.get("id", "")
    username = from_user.get("username", "")
    print(f"message||{from_id}|{username}|{text}")
else:
    print("")
PY
}

getUpdates() {
  # load data to variable
  local UPDATES=$(curl -s --location --request POST "https://api.telegram.org/bot$TELEGRAM_KEY/getUpdates" \
    --header 'Content-Type: application/json' \
    --data '{
        "offset": -1,
        "timeout": 0,
        "allowed_updates": ["callback_query", "message"]
    }')

  local PARSED
  PARSED=$(parse_latest_update "$UPDATES")
  if [ -z "$PARSED" ]; then
    echo "0|||"
    return
  fi

  local TYPE DATA FROM_ID USERNAME TEXT
  TYPE=$(echo "$PARSED" | cut -d '|' -f1)
  DATA=$(echo "$PARSED" | cut -d '|' -f2)
  FROM_ID=$(echo "$PARSED" | cut -d '|' -f3)
  USERNAME=$(echo "$PARSED" | cut -d '|' -f4)
  TEXT=$(echo "$PARSED" | cut -d '|' -f5-)

  if [ "$TYPE" = "callback" ]; then
    local APPROVE
    local REJECT
    APPROVE=$(echo "$DATA" | grep -o "a:$SESSION_ID")
    REJECT=$(echo "$DATA" | grep -o "r:$SESSION_ID")

    if [ -z "$APPROVE" ] && [ -z "$REJECT" ]; then
      echo "0|||"
    elif [ -n "$APPROVE" ]; then
      echo "1|$FROM_ID|$USERNAME|"
    elif [ -n "$REJECT" ]; then
      echo "2|$FROM_ID|$USERNAME|"
    fi
  elif [ "$TYPE" = "message" ]; then
    echo "3|$FROM_ID|$USERNAME|$TEXT"
  else
    echo "0|||"
  fi
}

updateMessage() {
  local text="$1"

  curl -s --location --request POST "https://api.telegram.org/bot$TELEGRAM_KEY/editMessageText" \
    --header 'Content-Type: application/json' \
    --data '{
        "chat_id": "'"$TELEGRAM_CHAT_ID"'",
        "message_id": "'"$MESSAGE_ID"'",
        "text": "'"$text"'"
    }'
}

format_approver_label() {
  local username="$1"
  local user_id="$2"

  if [ -n "$username" ]; then
    echo "@$username"
  else
    echo "user $user_id"
  fi
}

request_reject_reason() {
  local rejector_id="$1"
  local rejector_username="$2"
  local rejector_label
  rejector_label=$(format_approver_label "$rejector_username" "$rejector_id")

  sendRejectReasonRequest " from $rejector_label"

  local reason_counter=0
  while true; do
    local RESULT
    RESULT=$(getUpdates)
    local STATUS FROM_ID USERNAME TEXT
    STATUS=$(echo "$RESULT" | cut -d '|' -f1)
    FROM_ID=$(echo "$RESULT" | cut -d '|' -f2)
    USERNAME=$(echo "$RESULT" | cut -d '|' -f3)
    TEXT=$(echo "$RESULT" | cut -d '|' -f4-)

    if [ "$STATUS" = "3" ] && [ "$FROM_ID" = "$rejector_id" ] && [ -n "$TEXT" ]; then
      echo "$TEXT"
      return 0
    fi

    if [ $reason_counter -gt $UPDATE_REQUESTS ]; then
      echo ""
      return 1
    fi
    reason_counter=$((reason_counter + 1))
    sleep 1
  done
}

# Send message
sendMessage

# Wainting for approve or reject
UPDATE_REQUESTS_COUNTER=0
APPROVED_BY_IDS=""
APPROVED_COUNT=0
while true; do
  RESULT=$(getUpdates)
  echo "Result: $RESULT"

  STATUS=$(echo "$RESULT" | cut -d '|' -f1)
  FROM_ID=$(echo "$RESULT" | cut -d '|' -f2)
  USERNAME=$(echo "$RESULT" | cut -d '|' -f3)

  if [ "$STATUS" = "1" ] || [ "$STATUS" = "2" ]; then
    if ! is_user_allowed "$FROM_ID" "$USERNAME"; then
      echo "User is not allowed to approve."
      STATUS=0
    else
      GITHUB_USER=$(get_github_user_by_telegram_id "$FROM_ID" "$GITHUB_USERNAME_TO_TELEGRAM_USER_ID")
      if is_user_excluded "$FROM_ID" "$GITHUB_USER"; then
        echo "Workflow initiator is excluded from approvers."
        STATUS=0
      fi
    fi
  fi

  if [ "$STATUS" = "1" ]; then
    if ! is_in_list "$FROM_ID" "$APPROVED_BY_IDS"; then
      if [ -z "$APPROVED_BY_IDS" ]; then
        APPROVED_BY_IDS="$FROM_ID"
      else
        APPROVED_BY_IDS="$APPROVED_BY_IDS,$FROM_ID"
      fi
      APPROVED_COUNT=$((APPROVED_COUNT + 1))
    fi

    if [ "$APPROVED_COUNT" -ge "$APPROVAL_THRESHOLD" ]; then
      echo "Approved"
      APPROVER_LABEL=$(format_approver_label "$USERNAME" "$FROM_ID")
      updateMessage "$APPROVED_TEXT (by $APPROVER_LABEL)"
      exit 0
    else
      APPROVER_LABEL=$(format_approver_label "$USERNAME" "$FROM_ID")
      updateMessage "Approval received from $APPROVER_LABEL ($APPROVED_COUNT/$APPROVAL_THRESHOLD)"
    fi
  elif [ "$STATUS" = "2" ]; then
    echo "Rejected"
    APPROVER_LABEL=$(format_approver_label "$USERNAME" "$FROM_ID")
    if is_truthy "$REJECT_REASON_REQUIRED"; then
      REJECT_REASON=$(request_reject_reason "$FROM_ID" "$USERNAME")
      if [ -n "$REJECT_REASON" ]; then
        updateMessage "$REJECTED_TEXT (by $APPROVER_LABEL: $REJECT_REASON)"
      else
        updateMessage "$REJECTED_TEXT (by $APPROVER_LABEL)"
      fi
    else
      updateMessage "$REJECTED_TEXT (by $APPROVER_LABEL)"
    fi
    exit 1
  fi

  if [ $UPDATE_REQUESTS_COUNTER -gt $UPDATE_REQUESTS ]; then
    echo "Update requests limit reached"
    updateMessage "$TIMEOUT_TEXT"
    exit 1
  fi
  UPDATE_REQUESTS_COUNTER=$((UPDATE_REQUESTS_COUNTER + 1))
  echo "Waiting for approve or reject $UPDATE_REQUESTS_COUNTER/$UPDATE_REQUESTS"

  sleep 1
done
