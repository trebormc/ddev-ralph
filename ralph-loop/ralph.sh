#!/bin/bash

# =============================================================================
# Ralph Loop - Autonomous AI Task Orchestrator with Beads Integration
# =============================================================================
#
# Orchestrates AI agents autonomously with Beads (bd) task tracking.
# Delegates execution to separate OpenCode or Claude Code containers
# via docker exec — Ralph itself has NO AI tools installed.
#
#   PHASE 1 (Planning):   Agent reads requirements -> creates tasks in bd
#   PHASE 2+ (Execution): Agent works on tasks -> closes them -> repeats
#   EXIT:                 When bd ready returns empty [] -> COMPLETE
#
# AUTONOMOUS MODE:
#   OpenCode: docker exec $OPENCODE_CONTAINER opencode run ...
#   Claude:   docker exec $CLAUDE_CONTAINER claude -p ...
#
# Usage: ./ralph.sh [options]
#
# Options:
#   -b, --backend <tool>     Backend: opencode or claude (default: opencode)
#   -p, --prompt <file>      Requirements file (default: ./requirements.md)
#   -m, --model <model>      Model to use (default: backend's own default)
#   -i, --iterations <n>     Max iterations (default: 200)
#   -d, --delay <seconds>    Delay between iterations (default: 1)
#   --no-replan              Skip re-planning (resume existing tasks)
#   --no-beads               Run without Beads (legacy mode)
#   -h, --help               Show this help
#
# Backends (via docker exec to separate containers):
#   opencode  - Executes in ddev-{sitename}-opencode container
#   claude    - Executes in ddev-{sitename}-claude-code container
#
# Examples:
#   ./ralph.sh --backend opencode                  # OpenCode backend (default)
#   ./ralph.sh --backend claude                    # Claude Code backend
#   ./ralph.sh --backend claude --prompt my-project.md
#   ./ralph.sh --no-replan                         # Resume existing tasks
#   ./ralph.sh -b claude -m anthropic/claude-opus-4-5
#   ./ralph.sh --no-beads -p simple-task.md        # Legacy mode without Beads
# =============================================================================

set -euo pipefail

# =============================================================================
# Default configuration
# =============================================================================

PROMPT_FILE="./requirements.md"
MODEL=""
MAX_ITERATIONS=200
DELAY_SECONDS=1
REPLAN=true
USE_BEADS=true
BACKEND="opencode"

# Colors
R='\033[0m'
B='\033[1;34m'
GR='\033[1;32m'
Y='\033[1;33m'
RD='\033[1;31m'
CY='\033[1;36m'
M='\033[1;35m'
DIM='\033[2m'

SEP="════════════════════════════════════════════════════════════════════════════════"
SEP_THIN="────────────────────────────────────────────────────────────────────────────────"

# =============================================================================
# Parse arguments
# =============================================================================

show_help() {
  cat << 'EOF'
Ralph Loop - Autonomous AI Task Orchestrator with Beads Integration

Delegates to separate OpenCode or Claude Code containers via docker exec.
Ralph itself is a lightweight orchestrator (bash + jq + beads + docker CLI).

WORKFLOW:
  1. User writes requirements.md with project specifications
  2. Ralph runs Phase 1 (Planning): Agent creates tasks in Beads
  3. Ralph runs Phase 2+ (Execution): Agent works through tasks
  4. Loop exits when all tasks are completed (bd ready = [])

BACKENDS (separate DDEV containers):
  opencode  docker exec into ddev-{sitename}-opencode (requires ddev-opencode)
  claude    docker exec into ddev-{sitename}-claude-code (requires ddev-claude-code)

  Both achieve fully autonomous execution without permission prompts.
  Designed for overnight runs on well-defined, trusted tasks.

USAGE:
  ./ralph.sh [options]

OPTIONS:
  -b, --backend <tool>     Backend: opencode or claude (default: opencode)
  -p, --prompt <file>      Requirements file (default: ./requirements.md)
  -m, --model <model>      Model override (default: backend's own default)
  -i, --iterations <n>     Max iterations (default: 200)
  -d, --delay <seconds>    Delay between iterations (default: 1)
  --no-replan              Skip re-planning (resume existing tasks)
  --no-beads               Run without Beads integration (legacy mode)
  -h, --help               Show this help

DELAY RECOMMENDATIONS:
  0s    Maximum speed (overnight runs, no supervision needed)
  1s    Default (optimal balance, only 6% overhead)
  3-5s  Debugging/supervision (readable logs, easy to interrupt with Ctrl+C)

EXAMPLES:
  ./ralph.sh --backend opencode                              # OpenCode backend (default model)
  ./ralph.sh --backend claude                                # Claude Code backend (default model)
  ./ralph.sh -b claude --prompt my-project.md                # Custom requirements with Claude
  ./ralph.sh --no-replan                                     # Resume existing tasks
  ./ralph.sh -b claude -m anthropic/claude-sonnet-4-6        # Override model
  ./ralph.sh --no-beads -p simple-task.md                    # Legacy mode (no tracking)
  ./ralph.sh -b claude -i 500 -d 0                           # Overnight Claude run

EXIT CODES:
  0 - All tasks completed successfully
  1 - Error encountered
  2 - Max iterations reached

For more information, see: ralph-loop/README.md
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case $1 in
    -p|--prompt)
      PROMPT_FILE="$2"
      shift 2
      ;;
    -m|--model)
      MODEL="$2"
      shift 2
      ;;
    -i|--iterations)
      MAX_ITERATIONS="$2"
      shift 2
      ;;
    -d|--delay)
      DELAY_SECONDS="$2"
      shift 2
      ;;
    --no-replan)
      REPLAN=false
      shift
      ;;
    --no-beads)
      USE_BEADS=false
      shift
      ;;
    -b|--backend)
      BACKEND="$2"
      if [[ "$BACKEND" != "opencode" && "$BACKEND" != "claude" ]]; then
        echo -e "${RD}Error: --backend must be 'opencode' or 'claude'${R}"
        exit 1
      fi
      shift 2
      ;;
    -h|--help)
      show_help
      ;;
    *)
      echo -e "${RD}Error: Unknown option $1${R}"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

# =============================================================================
# Functions
# =============================================================================

START_TIME=$(date +%s)
START_DATE=$(date '+%Y-%m-%d %H:%M:%S')

format_time() {
  local secs=$1
  local hours=$((secs / 3600))
  local minutes=$(((secs % 3600) / 60))
  local seconds=$((secs % 60))

  if [[ $hours -gt 0 ]]; then
    printf "%dh %dm %ds" $hours $minutes $seconds
  elif [[ $minutes -gt 0 ]]; then
    printf "%dm %ds" $minutes $seconds
  else
    printf "%ds" $seconds
  fi
}

elapsed() {
  format_time $(($(date +%s) - START_TIME))
}

show_summary() {
  local status="$1"
  local iteration="$2"
  local color="$3"
  local tasks_completed="${4:-N/A}"
  local end_date=$(date '+%Y-%m-%d %H:%M:%S')
  local total=$(elapsed)

  echo ""
  echo -e "${color}${SEP}${R}"
  echo -e "${color}  RALPH LOOP - FINISHED${R}"
  echo -e "${color}${SEP}${R}"
  echo ""
  echo -e "  ${B}Result:${R}          ${color}${status}${R}"
  echo -e "  ${B}Backend:${R}         $BACKEND"
  echo -e "  ${B}Iterations:${R}      ${Y}${iteration}${R} / ${MAX_ITERATIONS}"
  if [[ "$USE_BEADS" == "true" ]]; then
    echo -e "  ${B}Tasks completed:${R} ${GR}${tasks_completed}${R}"
  fi
  echo -e "  ${B}Started:${R}         ${START_DATE}"
  echo -e "  ${B}Finished:${R}        ${end_date}"
  echo -e "  ${M}Total time:${R}      ${M}${total}${R}"
  echo ""
  echo -e "${color}${SEP}${R}"
}

check_beads_available() {
  if ! command -v bd &>/dev/null; then
    echo -e "${Y}Warning: bd (Beads) not found. Running in legacy mode.${R}"
    USE_BEADS=false
    return 1
  fi
  return 0
}

run_ai_tool() {
  local prompt="$1"
  local output=""
  local model_flag=""

  if [[ -n "$MODEL" ]]; then
    model_flag="--model $MODEL"
  fi

  case "$BACKEND" in
    opencode)
      # Execute in the OpenCode container via docker exec
      output=$(echo "$prompt" | docker exec -i \
        -e OPENCODE_PERMISSION='{"*":"allow"}' \
        -w /var/www/html \
        "$OPENCODE_CONTAINER" \
        opencode run $model_flag 2>&1) || true
      ;;
    claude)
      # Execute in the Claude Code container via docker exec
      output=$(echo "$prompt" | docker exec -i \
        -w /var/www/html \
        "$CLAUDE_CONTAINER" \
        claude -p $model_flag --dangerously-skip-permissions 2>&1) || true
      ;;
  esac

  echo "$output"
}

init_beads() {
  if [[ "$USE_BEADS" != "true" ]]; then
    return 0
  fi

  # Initialize Beads if not already initialized
  if [[ ! -d ".beads" ]]; then
    echo -e "${B}Initializing Beads task tracker...${R}"
    bd init --quiet 2>/dev/null || true
  fi
}

get_pending_tasks() {
  if [[ "$USE_BEADS" != "true" ]]; then
    echo "[]"
    return
  fi
  bd ready --json 2>/dev/null || echo "[]"
}

get_task_count() {
  local tasks="$1"
  echo "$tasks" | jq 'length' 2>/dev/null || echo "0"
}

clear_all_tasks() {
  if [[ "$USE_BEADS" != "true" ]]; then
    return 0
  fi

  echo -e "${Y}Re-planning: Clearing existing tasks...${R}"

  # Get all tasks and close them
  local all_tasks=$(bd ready --json 2>/dev/null || echo "[]")
  local task_ids=$(echo "$all_tasks" | jq -r '.[].id' 2>/dev/null || true)

  for task_id in $task_ids; do
    bd close "$task_id" --reason "Cleared for re-planning" --json 2>/dev/null || true
  done

  echo -e "${GR}Tasks cleared. Starting fresh planning phase.${R}"
}

# =============================================================================
# Validation
# =============================================================================

# Verify the target AI container is running
case "$BACKEND" in
  opencode)
    if ! docker inspect "$OPENCODE_CONTAINER" &>/dev/null; then
      echo -e "${RD}Error: OpenCode container ($OPENCODE_CONTAINER) is not running.${R}"
      echo -e "${Y}Install it first: ddev add-on get trebormc/ddev-opencode && ddev restart${R}"
      exit 1
    fi
    ;;
  claude)
    if ! docker inspect "$CLAUDE_CONTAINER" &>/dev/null; then
      echo -e "${RD}Error: Claude Code container ($CLAUDE_CONTAINER) is not running.${R}"
      echo -e "${Y}Install it first: ddev add-on get trebormc/ddev-claude-code && ddev restart${R}"
      exit 1
    fi
    ;;
esac

if [[ ! -f "$PROMPT_FILE" ]]; then
  echo -e "${RD}Error: Requirements file not found: $PROMPT_FILE${R}"
  echo -e "${Y}Create the file with your project requirements.${R}"
  echo ""
  echo "Example requirements.md:"
  echo "${SEP_THIN}"
  echo "# Project Requirements"
  echo ""
  echo "## Objective"
  echo "Create a REST API for user management."
  echo ""
  echo "## Requirements"
  echo "- User CRUD endpoints"
  echo "- Input validation"
  echo "- Unit tests with >80% coverage"
  echo "${SEP_THIN}"
  exit 1
fi

# Check for Beads availability
if [[ "$USE_BEADS" == "true" ]]; then
  check_beads_available
fi

# =============================================================================
# Header
# =============================================================================

echo -e "${CY}${SEP}${R}"
echo -e "${CY}  Ralph Loop${R}"
if [[ "$USE_BEADS" == "true" ]]; then
  echo -e "${CY}  with Beads Task Tracking${R}"
fi
echo -e "${CY}${SEP}${R}"
echo ""
echo -e "  ${B}Requirements:${R}  $PROMPT_FILE"
echo -e "  ${B}Model:${R}         ${MODEL:-${DIM}(backend default)${R}}"
echo -e "  ${B}Max iter:${R}      $MAX_ITERATIONS"
echo -e "  ${B}Delay:${R}         ${DELAY_SECONDS}s"
echo -e "  ${B}Beads:${R}         $(if [[ "$USE_BEADS" == "true" ]]; then echo -e "${GR}enabled${R}"; else echo -e "${Y}disabled${R}"; fi)"
echo -e "  ${B}Backend:${R}       $BACKEND"
echo -e "  ${B}Started:${R}       $START_DATE"
echo ""

# =============================================================================
# Initialize Beads
# =============================================================================

if [[ "$USE_BEADS" == "true" ]]; then
  init_beads

  # Handle --replan flag
  if [[ "$REPLAN" == "true" ]]; then
    clear_all_tasks
  fi
fi

# =============================================================================
# Determine initial phase
# =============================================================================

PHASE="execution"
TASKS_COMPLETED=0

if [[ "$USE_BEADS" == "true" ]]; then
  PENDING_TASKS=$(get_pending_tasks)
  PENDING_COUNT=$(get_task_count "$PENDING_TASKS")

  if [[ "$PENDING_COUNT" -eq 0 ]]; then
    # Check if there's any task history (closed tasks)
    ALL_TASKS=$(bd list --json 2>/dev/null || echo "[]")
    ALL_COUNT=$(echo "$ALL_TASKS" | jq 'length' 2>/dev/null || echo "0")

    if [[ "$ALL_COUNT" -eq 0 ]] || [[ "$REPLAN" == "true" ]]; then
      PHASE="planning"
      echo -e "${M}Phase: PLANNING${R} - Agent will analyze requirements and create tasks"
    else
      # All tasks completed from previous run
      echo -e "${GR}All tasks already completed!${R}"
      show_summary "ALREADY COMPLETE" "0" "$GR" "$ALL_COUNT"
      exit 0
    fi
  else
    echo -e "${M}Phase: EXECUTION${R} - Found ${Y}$PENDING_COUNT${R} pending tasks"
    echo -e "${DIM}$(echo "$PENDING_TASKS" | jq -r '.[] | "  - [\(.id)] \(.title)"' 2>/dev/null || true)${R}"
  fi
  echo ""
fi

# =============================================================================
# Main Loop
# =============================================================================

iteration=0

while true; do
  iteration=$((iteration + 1))

  # Check max iterations
  if [[ "$iteration" -gt "$MAX_ITERATIONS" ]]; then
    # Update task count before exiting
    if [[ "$USE_BEADS" == "true" ]]; then
      ALL_TASKS=$(bd list --json 2>/dev/null || echo "[]")
      TASKS_COMPLETED=$(echo "$ALL_TASKS" | jq '[.[] | select(.status == "closed")] | length' 2>/dev/null || echo "0")
    fi
    show_summary "MAX ITERATIONS REACHED" "$((iteration - 1))" "$Y" "$TASKS_COMPLETED"
    exit 2
  fi

  # ==========================================================================
  # Get current state (Beads mode)
  # ==========================================================================

  if [[ "$USE_BEADS" == "true" ]]; then
    PENDING_TASKS=$(get_pending_tasks)
    PENDING_COUNT=$(get_task_count "$PENDING_TASKS")

    # Check if all tasks are done (only after planning phase)
    if [[ "$PHASE" == "execution" ]] && [[ "$PENDING_COUNT" -eq 0 ]]; then
      # Get completed task count for summary
      ALL_TASKS=$(bd list --json 2>/dev/null || echo "[]")
      TASKS_COMPLETED=$(echo "$ALL_TASKS" | jq '[.[] | select(.status == "closed")] | length' 2>/dev/null || echo "0")

      # Exit when no pending tasks, regardless of completed count
      # (TASKS_COMPLETED might be 0 if bd list fails or in fresh runs)
      show_summary "ALL TASKS COMPLETED" "$iteration" "$GR" "$TASKS_COMPLETED"
      exit 0
    fi
  fi

  # ==========================================================================
  # Display iteration header
  # ==========================================================================

  echo -e "${B}${SEP}${R}"
  if [[ "$PHASE" == "planning" ]]; then
    echo -e "  ${M}PLANNING PHASE${R}  |  ${B}Elapsed: $(elapsed)${R}  |  ${DIM}Backend: $BACKEND${R}"
  else
    echo -e "  ${GR}Iteration ${Y}$iteration${R}/${MAX_ITERATIONS}  |  ${B}Elapsed: $(elapsed)${R}  |  ${DIM}Backend: $BACKEND${R}"
    if [[ "$USE_BEADS" == "true" ]]; then
      echo -e "  ${DIM}Pending tasks: $PENDING_COUNT${R}"
    fi
  fi
  echo -e "${B}${SEP}${R}"
  echo ""

  ITER_START=$(date +%s)

  # ==========================================================================
  # Build prompt based on phase
  # ==========================================================================

  if [[ "$PHASE" == "planning" ]]; then
    # ========================================================================
    # PLANNING PHASE PROMPT
    # ========================================================================
    PROMPT="[RALPH LOOP - PLANNING PHASE]

You are starting a new project. Your task is to analyze the requirements and create a structured task list using Beads (bd).

## Requirements

$(cat "$PROMPT_FILE")

---

## Your Task (Planning Phase)

1. **Analyze** the requirements carefully
2. **Break down** the work into discrete, actionable tasks
3. **Create tasks** in Beads using the bd command:

\`\`\`bash
bd create \"Task title\" -p <priority> --json
\`\`\`

Priority levels:
- P0: Critical blockers, security issues
- P1: Core functionality (most tasks should be P1)
- P2: Secondary features, enhancements
- P3: Nice-to-have, polish

4. **Order matters**: Create tasks in the order they should be executed
5. **Be specific**: Each task should be completable in 1-3 iterations

### Example task creation:

\`\`\`bash
bd create \"Set up project structure and dependencies\" -p 1 --json
bd create \"Implement user authentication service\" -p 1 --json
bd create \"Write unit tests for auth service\" -p 1 --json
bd create \"Add input validation\" -p 2 --json
bd create \"Write API documentation\" -p 2 --json
\`\`\`

---

## Completion Signal

When you have created ALL necessary tasks, output exactly:
\`\`\`
<promise>PLANNING_COMPLETE</promise>
\`\`\`

Do NOT start working on tasks yet. Only create the task list."

  else
    # ========================================================================
    # EXECUTION PHASE PROMPT
    # ========================================================================

    if [[ "$USE_BEADS" == "true" ]]; then
      # Get highest priority task
      CURRENT_TASK=$(echo "$PENDING_TASKS" | jq '.[0]' 2>/dev/null || echo "{}")
      TASK_ID=$(echo "$CURRENT_TASK" | jq -r '.id // empty' 2>/dev/null || true)
      TASK_TITLE=$(echo "$CURRENT_TASK" | jq -r '.title // empty' 2>/dev/null || true)
      TASK_PRIORITY=$(echo "$CURRENT_TASK" | jq -r '.priority // empty' 2>/dev/null || true)

      PROMPT="[RALPH LOOP - Iteration $iteration of $MAX_ITERATIONS]

## Current Task

**ID:** $TASK_ID
**Title:** $TASK_TITLE
**Priority:** P$TASK_PRIORITY

## All Pending Tasks

\`\`\`json
$PENDING_TASKS
\`\`\`

## Original Requirements

$(cat "$PROMPT_FILE")

---

## Instructions

1. **Mark task in progress:**
   \`\`\`bash
   bd update $TASK_ID --status in_progress
   \`\`\`

2. **Work on the current task** until completion

3. **If you discover new subtasks or issues**, create them:
   \`\`\`bash
   bd create \"New task description\" -p 2 --json
   \`\`\`

4. **When the current task is complete**, close it:
   \`\`\`bash
   bd close $TASK_ID --reason \"Brief description of what was done\" --json
   \`\`\`

5. **Add progress notes** if pausing mid-task:
   \`\`\`bash
   bd update $TASK_ID --notes \"Progress: implemented X, still need Y\"
   \`\`\`

---

## Completion Signals

- If you **completed a task** but there are **more pending**: Just close the task and end the iteration
- If you **encounter an unrecoverable error**:
  \`\`\`
  <promise>ERROR</promise>
  \`\`\`

Do NOT output COMPLETE - the loop automatically detects completion when bd ready returns empty."

    else
      # Legacy mode (no Beads)
      PROMPT="[RALPH LOOP - Iteration $iteration of $MAX_ITERATIONS]

$(cat "$PROMPT_FILE")

---

## IMPORTANT: Completion Signal

When you have COMPLETED ALL tasks described above, you MUST output exactly:
\`\`\`
<promise>COMPLETE</promise>
\`\`\`

If you encounter an unrecoverable error that prevents completion, output:
\`\`\`
<promise>ERROR</promise>
\`\`\`

Do NOT continue working after outputting a completion signal."
    fi
  fi

  # ==========================================================================
  # Run AI Tool
  # ==========================================================================

  OUTPUT=$(run_ai_tool "$PROMPT")

  echo "$OUTPUT"

  ITER_TIME=$(($(date +%s) - ITER_START))
  echo ""
  echo -e "  ${B}Iteration completed in ${Y}$(format_time $ITER_TIME)${R}"

  # ==========================================================================
  # Check signals and state
  # ==========================================================================

  # Check for planning completion
  if [[ "$PHASE" == "planning" ]]; then
    if echo "$OUTPUT" | grep -q "<promise>PLANNING_COMPLETE</promise>"; then
      echo ""
      echo -e "${GR}Planning complete!${R} Switching to execution phase."
      PHASE="execution"

      # Show created tasks
      if [[ "$USE_BEADS" == "true" ]]; then
        PENDING_TASKS=$(get_pending_tasks)
        PENDING_COUNT=$(get_task_count "$PENDING_TASKS")
        echo -e "Created ${Y}$PENDING_COUNT${R} tasks:"
        echo -e "${DIM}$(echo "$PENDING_TASKS" | jq -r '.[] | "  - [P\(.priority)] \(.title)"' 2>/dev/null || true)${R}"
      fi

      echo ""
      echo -e "${Y}Starting execution in ${DELAY_SECONDS}s...${R}"
      sleep $DELAY_SECONDS
      continue
    fi
  fi

  # Check for error signal
  if echo "$OUTPUT" | grep -q "<promise>ERROR</promise>"; then
    if [[ "$USE_BEADS" == "true" ]]; then
      TASKS_COMPLETED=$(bd list --json 2>/dev/null | jq '[.[] | select(.status == "closed")] | length' 2>/dev/null || echo "0")
    fi
    show_summary "ERROR" "$iteration" "$RD" "$TASKS_COMPLETED"
    exit 1
  fi

  # Check for legacy COMPLETE signal (only in non-Beads mode)
  if [[ "$USE_BEADS" != "true" ]]; then
    if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
      show_summary "COMPLETED" "$iteration" "$GR"
      exit 0
    fi
  fi

  # ==========================================================================
  # Next iteration
  # ==========================================================================

  echo ""
  echo -e "${Y}Next iteration in ${DELAY_SECONDS}s...${R}"
  sleep $DELAY_SECONDS
done
