# AI Functions - Gemini
# Requires the GEMINI_API_KEY variable (loaded from ~/logins.sh)

# Token threshold settings (80% of 1,048,576 limit = ~838,860 tokens)
GEMINI_MAX_INPUT_TOKENS=1048576
GEMINI_COMPRESSION_THRESHOLD=838860
# Truncate extremely large single command outputs (>25KB) to prevent instant context overflow
MAX_OUTPUT_BYTES=25000

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

# Helper to compress history
_compress_gemini_history() {
  local history_file="$1"
  local sys_file="$2"
  local temp_file="$3"

  local history_len=$(jq 'length' "$history_file")
  if [ "$history_len" -le 2 ]; then
    return 0
  fi

  echo -e "\033[1;33m[History reached 80% token quota. Compressing older conversation history...]\033[0m"

  local older_history=$(jq '.[0:-1]' "$history_file")
  local last_turn=$(jq '.[-1]' "$history_file")

  local summarize_prompt="You are a context compression assistant. Summarize the following conversation history into a concise, high-density structured context summary. You MUST preserve:
1. The active overall goal and task state.
2. Key files created, modified, or examined.
3. Crucial command results and system status.
4. Any explicit user preferences or constraints.

Conversation history to summarize:
${older_history}"

  echo -n "$summarize_prompt" > "$temp_file"
  jq -n --rawfile sys "$sys_file" --rawfile prompt "$temp_file" \
    '{system_instruction: {parts: [{text: $sys}]}, contents: [{role: "user", parts: [{text: $prompt}]}]}' > "${temp_file}.payload"

  local summary_response=$(curl -s -H "Content-Type: application/json" -d @"${temp_file}.payload" "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent?key=$GEMINI_API_KEY")
  rm -f "${temp_file}.payload"

  local summary_text=$(echo "$summary_response" | jq -r '.candidates[0].content.parts[0].text // empty')

  if [ -n "$summary_text" ]; then
    local summary_entry=$(jq -n --arg sum "--- COMPRESSED PREVIOUS CONVERSATION CONTEXT SUMMARY ---
$summary_text" '[{role: "user", parts: [{text: $sum}]}, {role: "model", parts: [{text: "Understood. I have restored context from the compressed summary and am ready to continue."}]}]')

    jq -n --argjson summary "$summary_entry" --argjson last "[$last_turn]" '$summary + $last' > "${history_file}.tmp" && mv "${history_file}.tmp" "$history_file"
    echo -e "\033[1;32m[History compression complete.]\033[0m"
  else
    echo -e "\033[1;31m[History compression failed, keeping existing history.]\033[0m"
  fi
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
  
  local history_file=$(mktemp)
  local sys_file=$(mktemp)
  local temp_file=$(mktemp)
  
  echo "[]" > "$history_file"
  echo -n "$system_instruction" > "$sys_file"

  trap 'rm -f "$history_file" "$sys_file" "$temp_file"' EXIT INT TERM

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

    # Append user input safely via temp file to avoid ARG_MAX limit
    echo -n "$user_input" > "$temp_file"
    jq --rawfile input "$temp_file" '. + [{role: "user", parts: [{text: $input}]}]' "$history_file" > "${history_file}.tmp" && mv "${history_file}.tmp" "$history_file"

    while true; do
      jq -n \
        --rawfile sys "$sys_file" \
        --slurpfile contents "$history_file" \
        '{system_instruction: {parts: [{text: $sys}]}, contents: $contents[0]}' > "$temp_file"

      local response=$(curl -s -H "Content-Type: application/json" -d @"$temp_file" "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent?key=$GEMINI_API_KEY")
      
      echo "$response" > "$temp_file"
      local text_out=$(jq -r '.candidates[0].content.parts[0].text // empty' "$temp_file")
      local finish_reason=$(jq -r '.candidates[0].finishReason // empty' "$temp_file")
      local prompt_tokens=$(jq -r '.usageMetadata.promptTokenCount // 0' "$temp_file")

      if [ -z "$text_out" ]; then
        # Gemini 3 sometimes tries to call a native tool instead of returning text.
        if [ "$finish_reason" = "MALFORMED_FUNCTION_CALL" ] && [ "$retries" -lt 3 ]; then
          retries=$((retries + 1))
          echo -e "\033[1;33m[Model tried to use a tool - retrying ($retries/3)...]\033[0m"
          local nudge="ERROR: Do not call functions/tools (function calling). Return the command ONLY as plain text inside a \`\`\`bash ... \`\`\` block."
          echo -n "$nudge" > "$temp_file"
          jq --rawfile n "$temp_file" '. + [{role: "user", parts: [{text: $n}]}]' "$history_file" > "${history_file}.tmp" && mv "${history_file}.tmp" "$history_file"
          continue
        fi
        echo -e "\033[1;31mAPI response error (finishReason: ${finish_reason:-none}).\033[0m"
        echo -e "\033[1;33m[Sent prompt/payload]:\033[0m"
        jq . "$temp_file"
        echo -e "\033[1;31m[API response]:\033[0m"
        echo "$response"
        break
      fi

      # Check if prompt token count exceeds 80% quota threshold
      if [ "$prompt_tokens" -ge "${GEMINI_COMPRESSION_THRESHOLD:-838860}" ]; then
        _compress_gemini_history "$history_file" "$sys_file" "$temp_file"
      fi

      retries=0
      echo -n "$text_out" > "$temp_file"
      jq --rawfile model_text "$temp_file" '. + [{role: "model", parts: [{text: $model_text}]}]' "$history_file" > "${history_file}.tmp" && mv "${history_file}.tmp" "$history_file"

      if echo "$text_out" | grep -q '```bash'; then
        local cmd=$(echo "$text_out" | awk '/```bash/{flag=1; next} /```/{if(flag) exit} flag')
        echo -e "\n\033[1;36m[Gemini]:\033[0m $text_out"
        echo -e "\033[1;33m[Command to execute]:\033[0m\n\033[1;32m$cmd\033[0m"
        
        local raw_output=$(bash -c "set -x; $cmd" 2>&1)
        echo -e "\033[0;36m$raw_output\033[0m"
        
        local output="$raw_output"
        local output_size=${#raw_output}
        if [ "$output_size" -gt "${MAX_OUTPUT_BYTES:-25000}" ]; then
          local head_part="${raw_output:0:10000}"
          local tail_part="${raw_output: -10000}"
          output="${head_part}

... [OUTPUT TRUNCATED: ${output_size} bytes total (showing first 10KB & last 10KB)] ...

${tail_part}"
          echo -e "\033[1;33m[Command output truncated from ${output_size} to ~20KB for token optimization]\033[0m"
        fi
        
        local sys_msg="Output of command '$cmd':
$output"
        echo -n "$sys_msg" > "$temp_file"
        jq --rawfile sys_msg "$temp_file" '. + [{role: "user", parts: [{text: $sys_msg}]}]' "$history_file" > "${history_file}.tmp" && mv "${history_file}.tmp" "$history_file"
      else
        echo -e "\n\033[1;36m[Gemini]:\033[0m $text_out\n"
        break
      fi
    done
  done
}
