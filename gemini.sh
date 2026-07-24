# AI Functions - Gemini
# Requires the GEMINI_API_KEY variable (loaded from ~/logins.sh)

# Alias for simple questions
gemini() {
  if [ -z "$1" ]; then
    echo "Usage: gemini \"Your question\""
    return 1
  fi

  curl -s -H "Content-Type: application/json" \
    -d "{\"contents\":[{\"parts\":[{\"text\":\"$1\"}]}]}" \
    "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent?key=$GEMINI_API_KEY" \
    | grep -o '"text": "[^"]*"' | sed 's/"text": "//;s/"$//'
}

# Autonomous agent in PWD with a live view of actions in the shell
gemini-chat() {
  local pwd_path=$(pwd)
  local env_instructions=""

  if [ -n "${AI_FEATURES:-}" ]; then
    local _file
    local _files=$(echo "$AI_FEATURES" | tr ':' ' ')
    for _file in $_files; do
      if [ -f "$_file" ]; then
        local _content
        _content=$(cat "$_file")
        if [ -n "$_content" ]; then
          env_instructions="${env_instructions}

--- Environment Documentation ($_file) ---
${_content}"
        fi
      fi
    done
  fi

  local system_instruction="You are an autonomous CLI agent working directly in the directory: ${pwd_path}. You have full permissions to create and modify files and run commands. IMPORTANT: You do NOT have access to any tools or function calling - do not call functions such as run_bash. To execute a command, return it ONLY as plain text inside a bash block: \`\`\`bash\ncommand\n\`\`\`. Perform the steps autonomously until you reach the goal given by the user. When you are done, provide a concise summary without a bash block.${env_instructions}"
  
  local history="[]"
  local retries=0
  
  echo -e "\033[1;32m=== Autonomous Gemini Agent in: ${pwd_path} ===\033[0m"
  echo -e "Type \033[1;33mexit\033[0m or \033[1;33mquit\033[0m to end the session.\n"

  while true; do
    echo -n "Chat > "
    local user_input=""
    local line
    
    if ! IFS= read -r line; then
      break
    fi

    if [ "$line" = "exit" ] || [ "$line" = "quit" ]; then
      echo "Session ended."
      break
    fi

    user_input="$line"

    # Read remaining buffered input (e.g. multiline paste) with 0.1s timeout
    while IFS= read -r -t 0.1 line; do
      user_input="$user_input
$line"
    done
    
    if [ -z "$user_input" ]; then
      continue
    fi

    history=$(echo "$history" | jq --arg input "$user_input" '. + [{role: "user", parts: [{text: $input}]}]')

    while true; do
      local payload=$(jq -n \
        --arg sys "$system_instruction" \
        --argjson contents "$history" \
        '{system_instruction: {parts: [{text: $sys}]}, contents:$contents}')

      local response=$(curl -s -H "Content-Type: application/json" -d "$payload" "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent?key=$GEMINI_API_KEY")
      local text_out=$(echo "$response" | jq -r '.candidates[0].content.parts[0].text // empty')
      local finish_reason=$(echo "$response" | jq -r '.candidates[0].finishReason // empty')

      if [ -z "$text_out" ]; then
        # Gemini 3 sometimes tries to call a native tool instead of returning text.
        if [ "$finish_reason" = "MALFORMED_FUNCTION_CALL" ] && [ "$retries" -lt 3 ]; then
          retries=$((retries + 1))
          echo -e "\033[1;33m[Model tried to use a tool - retrying ($retries/3)...]\033[0m"
          local nudge="ERROR: Do not call functions/tools (function calling). Return the command ONLY as plain text inside a \`\`\`bash ... \`\`\` block."
          history=$(echo "$history" | jq --arg n "$nudge" '. + [{role: "user", parts: [{text: $n}]}]')
          continue
        fi
        echo -e "\033[1;31mAPI response error (finishReason: ${finish_reason:-none}).\033[0m"
        echo -e "\033[1;33m[Sent prompt/payload]:\033[0m"
        echo "$payload" | jq .
        echo -e "\033[1;31m[API response]:\033[0m"
        echo "$response"
        break
      fi

      retries=0
      history=$(echo "$history" | jq --arg model_text "$text_out" '. + [{role: "model", parts: [{text: $model_text}]}]')

      if echo "$text_out" | grep -q '```bash'; then
        local cmd=$(echo "$text_out" | awk '/```bash/{flag=1; next} /```/{if(flag) exit} flag')
        echo -e "\n\033[1;36m[Gemini]:\033[0m $text_out"
        echo -e "\033[1;33m[Command to execute]:\033[0m\n\033[1;32m$cmd\033[0m"
        
        local output=$(bash -c "set -x; $cmd" 2>&1)
        echo -e "\033[0;36m$output\033[0m"
        
        local sys_msg="Output of command '$cmd':
$output"
        history=$(echo "$history" | jq --arg sys_msg "$sys_msg" '. + [{role: "user", parts: [{text: $sys_msg}]}]')
      else
        echo -e "\n\033[1;36m[Gemini]:\033[0m $text_out\n"
        break
      fi
    done
  done
}
