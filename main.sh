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
ALLOW_GITHUB_RERUN_ON_TIMEOUT="true"
RERUN_BUTTON="Rerun workflow"
RERUN_TEXT="Rerun requested."
RERUN_FAILED_TEXT="Rerun failed."
RERUN_WORKFLOW_FILE=""
RERUN_REF=""
LAST_RERUN_STATUS=""

# Define long options
LONGOPTS=TELEGRAM_KEY:,TELEGRAM_CHAT_ID:,UPDATE_REQUESTS:,APPROVAL_TEXT:,APPROVAL_BUTTON:,REJECT_BUTTON:,APPROVED_TEXT:,REJECTED_TEXT:,TIMEOUT_TEXT:,ALLOW_GITHUB_RERUN_ON_TIMEOUT:,RERUN_BUTTON:,RERUN_TEXT:,RERUN_FAILED_TEXT:,RERUN_WORKFLOW_FILE:,RERUN_REF:

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
    --ALLOW_GITHUB_RERUN_ON_TIMEOUT)
      ALLOW_GITHUB_RERUN_ON_TIMEOUT="$2"
      shift 2
      ;;
    --RERUN_BUTTON)
      RERUN_BUTTON="$2"
      shift 2
      ;;
    --RERUN_TEXT)
      RERUN_TEXT="$2"
      shift 2
      ;;
    --RERUN_FAILED_TEXT)
      RERUN_FAILED_TEXT="$2"
      shift 2
      ;;
    --RERUN_WORKFLOW_FILE)
      RERUN_WORKFLOW_FILE="$2"
      shift 2
      ;;
    --RERUN_REF)
      RERUN_REF="$2"
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

# Logic

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
echo "Session ID: $SESSION_ID"

MESSAGE_ID=""

getGithubToken() {
  if [ -n "$GITHUB_TOKEN" ]; then
    echo "$GITHUB_TOKEN"
  else
    echo ""
  fi
}

extractWorkflowFromValue() {
  local value="$1"

  if [[ "$value" == *".github/workflows/"* ]]; then
    local after="${value#*.github/workflows/}"
    after="${after%@*}"
    echo "$after"
  fi
}

getDispatchWorkflowFile() {
  if [ -n "$RERUN_WORKFLOW_FILE" ]; then
    echo "$RERUN_WORKFLOW_FILE"
    return
  fi

  local extracted
  extracted=$(extractWorkflowFromValue "$GITHUB_WORKFLOW_REF")
  if [ -n "$extracted" ]; then
    echo "$extracted"
    return
  fi

  extracted=$(extractWorkflowFromValue "$GITHUB_WORKFLOW")
  if [ -n "$extracted" ]; then
    echo "$extracted"
    return
  fi

  if [ -n "$GITHUB_WORKFLOW" ]; then
    if [[ "$GITHUB_WORKFLOW" == *.yml ]] || [[ "$GITHUB_WORKFLOW" == *.yaml ]]; then
      echo "$GITHUB_WORKFLOW"
      return
    fi
  fi
}

getDispatchRef() {
  if [ -n "$RERUN_REF" ]; then
    echo "$RERUN_REF"
    return
  fi

  if [ -n "$GITHUB_BASE_REF" ]; then
    echo "$GITHUB_BASE_REF"
    return
  fi

  if [ -n "$GITHUB_REF_NAME" ]; then
    if [[ "$GITHUB_REF_NAME" != */merge ]]; then
      echo "$GITHUB_REF_NAME"
      return
    fi
  fi

  if [[ "$GITHUB_REF" == refs/heads/* ]]; then
    echo "${GITHUB_REF#refs/heads/}"
    return
  fi
  if [[ "$GITHUB_REF" == refs/tags/* ]]; then
    echo "${GITHUB_REF#refs/tags/}"
    return
  fi
}

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

getUpdates() {
  # load data to variable
  local UPDATES=$(curl -s --location --request POST "https://api.telegram.org/bot$TELEGRAM_KEY/getUpdates" \
    --header 'Content-Type: application/json' \
    --data '{
        "offset": -1,
        "timeout": 0,
        "allowed_updates": ["callback_query"]
    }')
  
  # search for a:$SESSION_ID, r:$SESSION_ID, or g:$SESSION_ID as: "data": "r:xxxxxxxxx"
  local DATA=$(echo $UPDATES | awk -F '"data":' '{print $2}' | awk -F '}' '{print $1}')
  local APPROVE=$(echo $DATA | grep -o "a:$SESSION_ID")
  local REJECT=$(echo $DATA | grep -o "r:$SESSION_ID")
  local RERUN=""
  if [ "$ALLOW_GITHUB_RERUN_ON_TIMEOUT" = "true" ]; then
    RERUN=$(echo $DATA | grep -o "g:$SESSION_ID")
  fi

  if [ -z "$APPROVE" ] && [ -z "$REJECT" ] && [ -z "$RERUN" ]; then
    echo 0
  elif [ -n "$APPROVE" ]; then
    echo 1
  elif [ -n "$REJECT" ]; then
    echo 2
  elif [ -n "$RERUN" ]; then
    echo 3
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

updateMessageClearButtons() {
  local text="$1"

  curl -s --location --request POST "https://api.telegram.org/bot$TELEGRAM_KEY/editMessageText" \
    --header 'Content-Type: application/json' \
    --data '{
        "chat_id": "'"$TELEGRAM_CHAT_ID"'",
        "message_id": "'"$MESSAGE_ID"'",
        "text": "'"$text"'",
        "reply_markup": {"inline_keyboard": []}
    }'
}

buildTimeoutButtons() {
  local buttons=""

  if [ "$ALLOW_GITHUB_RERUN_ON_TIMEOUT" = "true" ]; then
    buttons="{\"text\": \"${RERUN_BUTTON}\", \"callback_data\": \"g:${SESSION_ID}\"}"
  fi

  echo "$buttons"
}

updateMessageWithTimeoutButtons() {
  local text="$1"
  local buttons
  buttons=$(buildTimeoutButtons)

  curl -s --location --request POST "https://api.telegram.org/bot$TELEGRAM_KEY/editMessageText" \
    --header 'Content-Type: application/json' \
    --data '{
        "chat_id": "'"$TELEGRAM_CHAT_ID"'",
        "message_id": "'"$MESSAGE_ID"'",
        "text": "'"$text"'",
        "reply_markup": {
            "inline_keyboard": [
                [
                    '"$buttons"'
                ]
            ]
        }
    }'
}

timeoutWaitLabel() {
  if [ "$ALLOW_GITHUB_RERUN_ON_TIMEOUT" = "true" ]; then
    echo "rerun"
  else
    echo "response"
  fi
}

rerunFailedMessage() {
  if [ -n "$LAST_RERUN_STATUS" ]; then
    echo "${RERUN_FAILED_TEXT} (status $LAST_RERUN_STATUS)"
  else
    echo "$RERUN_FAILED_TEXT"
  fi
}

dispatchWorkflow() {
  local token="$1"
  local workflow_file="$2"
  local ref="$3"
  local status

  if [ -z "$token" ]; then
    echo "Missing GitHub token for dispatch"
    LAST_RERUN_STATUS="missing-token"
    return 2
  fi
  if [ -z "$GITHUB_REPOSITORY" ]; then
    echo "Missing GITHUB_REPOSITORY"
    LAST_RERUN_STATUS="missing-repo"
    return 3
  fi
  if [ -z "$workflow_file" ] || [ -z "$ref" ]; then
    echo "Missing workflow file or ref for dispatch"
    LAST_RERUN_STATUS="missing-workflow-or-ref"
    return 4
  fi

  status=$(curl -s -o /dev/null -w "%{http_code}" \
    --location \
    --request POST \
    --header "Authorization: Bearer $token" \
    --header "Accept: application/vnd.github+json" \
    --header "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/$GITHUB_REPOSITORY/actions/workflows/$workflow_file/dispatches" \
    --data '{"ref":"'"$ref"'"}')

  LAST_RERUN_STATUS="$status"
  if [ "$status" -ge 200 ] && [ "$status" -lt 300 ]; then
    return 0
  fi

  echo "Workflow dispatch failed with status $status"
  return 1
}

# Send message
sendMessage

# Waiting for approve or reject
UPDATE_REQUESTS_COUNTER=0
STATE="waiting"
while true; do
  RESULT=$(getUpdates)
  echo "Result: $RESULT"

  if [ $RESULT -eq 1 ]; then
    echo "Approved"
    updateMessageClearButtons "$APPROVED_TEXT"
    exit 0
  elif [ $RESULT -eq 2 ]; then
    echo "Rejected"
    updateMessageClearButtons "$REJECTED_TEXT"
    exit 1
  elif [ $RESULT -eq 3 ]; then
    if [ "$STATE" = "timeout" ]; then
      echo "Rerun requested"
      LAST_RERUN_STATUS=""
      token=$(getGithubToken)
      workflow_file=$(getDispatchWorkflowFile)
      ref=$(getDispatchRef)
      if [ -n "$workflow_file" ] && [ -n "$ref" ]; then
        echo "Attempting workflow dispatch for $workflow_file@$ref"
        if dispatchWorkflow "$token" "$workflow_file" "$ref"; then
          updateMessageClearButtons "$RERUN_TEXT"
        else
          updateMessageClearButtons "$(rerunFailedMessage)"
        fi
      else
        LAST_RERUN_STATUS="missing-workflow-or-ref"
        updateMessageClearButtons "$(rerunFailedMessage)"
      fi
      exit 1
    fi
  fi

  if [ "$STATE" = "waiting" ]; then
    if [ $UPDATE_REQUESTS_COUNTER -gt $UPDATE_REQUESTS ]; then
      echo "Update requests limit reached"
      if [ "$ALLOW_GITHUB_RERUN_ON_TIMEOUT" = "true" ]; then
        updateMessageWithTimeoutButtons "$TIMEOUT_TEXT"
        STATE="timeout"
        UPDATE_REQUESTS_COUNTER=0
        continue
      else
        updateMessageClearButtons "$TIMEOUT_TEXT"
        exit 1
      fi
    fi
  else
    if [ $UPDATE_REQUESTS_COUNTER -gt $UPDATE_REQUESTS ]; then
      echo "Rerun window expired"
      updateMessageClearButtons "$TIMEOUT_TEXT"
      exit 1
    fi
  fi
  UPDATE_REQUESTS_COUNTER=$((UPDATE_REQUESTS_COUNTER + 1))
  if [ "$STATE" = "waiting" ]; then
    echo "Waiting for approve or reject $UPDATE_REQUESTS_COUNTER/$UPDATE_REQUESTS"
  else
    echo "Waiting for $(timeoutWaitLabel) $UPDATE_REQUESTS_COUNTER/$UPDATE_REQUESTS"
  fi

  sleep 1
done
