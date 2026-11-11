#!/bin/bash
#ddev-generated

# =============================================================================
# Ralph Loop - Autonomous AI Task Orchestrator with Beads Integration
# =============================================================================
#
# Orchestrates AI agents autonomously with Beads (bd) task tracking.
# Delegates execution to separate OpenCode or Claude Code containers
# via SSH — Ralph itself has NO AI tools installed.
#
#   PHASE 1 (Planning):   Agent reads requirements -> creates tasks in bd
#   PHASE 2+ (Execution): Agent works on tasks -> closes them -> repeats
#   EXIT:                 When bd ready returns empty [] -> COMPLETE
#   ABORT:                3 consecutive Beads or backend failures, a plan
#                         with no tasks, or tasks still open after 3 attempts
#
# AUTONOMOUS MODE:
#   OpenCode: ssh opencode opencode run ...
#   Claude:   ssh claude-code claude -p ...
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
# Backends (via SSH to separate containers):
#   opencode  - Executes in opencode container via SSH
#   claude    - Executes in claude-code container via SSH
#
# Examples:
#   ./ralph.sh --backend opencode                  # OpenCode backend (default)
#   ./ralph.sh --backend claude                    # Claude Code backend
#   ./ralph.sh --backend claude --prompt my-project.md
#   ./ralph.sh --no-replan                         # Resume existing tasks
#   ./ralph.sh -b claude -m opus                   # Claude Code: alias or full model name
#   ./ralph.sh -b opencode -m anthropic/claude-opus-4-5   # OpenCode: provider/model
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

# Safety limits
MAX_CONSECUTIVE_FAILURES=3   # Beads or backend failures in a row before aborting
MAX_TASK_ATTEMPTS=3          # Iterations spent on one task before it is set aside
MAX_PLANNING_ATTEMPTS=3      # Planning iterations that may end without any task

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

Delegates to separate OpenCode or Claude Code containers via SSH.
Ralph itself is a lightweight orchestrator (bash + jq + beads).

WORKFLOW:
  1. User writes requirements.md with project specifications
  2. Ralph runs Phase 1 (Planning): Agent creates tasks in Beads
  3. Ralph runs Phase 2+ (Execution): Agent works through tasks
  4. Loop exits when all tasks are completed (bd ready = [])

BACKENDS (separate DDEV containers via SSH):
  opencode  SSH into opencode container (requires ddev-opencode)
  claude    SSH into claude-code container (requires ddev-claude-code)

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
  ./ralph.sh -b claude -m sonnet                             # Override model (Claude Code: alias or full model name)
  ./ralph.sh -b opencode -m anthropic/claude-sonnet-4-6      # Override model (OpenCode: provider/model)
  ./ralph.sh --no-beads -p simple-task.md                    # Legacy mode (no tracking)
  ./ralph.sh -b claude -i 500 -d 0                           # Overnight Claude run

EXIT CODES:
  0 - All tasks completed successfully
  1 - Error: agent signalled ERROR, Beads or the backend failed 3 times in a
      row, planning created no tasks, or tasks stayed open after 3 attempts
  2 - Max iterations reached

For more information, see: https://github.com/trebormc/ddev-ralph
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

# Prints the backend output and returns the backend's exit code, so the loop
# can tell a dead backend (auth error, wrong model, SSH down) from a normal run.
run_ai_tool() {
  local prompt="$1"
  local output=""
  local model_flag=""
  local rc=0

  if [[ -n "$MODEL" ]]; then
    model_flag="--model $MODEL"
  fi

  case "$BACKEND" in
    opencode)
      # Execute in the OpenCode container via SSH (OpenCode 2).
      # --auto: approve every permission not explicitly denied by the config
      #         (OpenCode 2 ignores the OPENCODE_PERMISSION env var).
      # --standalone: private server per run instead of the shared background
      #         service, so the run owns its environment and exits cleanly.
      output=$(echo "$prompt" | ssh opencode \
        "opencode run --standalone --auto $model_flag" 2>&1) || rc=$?
      ;;
    claude)
      # Execute in the Claude Code container via SSH.
      # Never add --bare: it skips the user-level settings (git-policy hook)
      # and the orchestrator CLAUDE.md, agents and skills.
      output=$(echo "$prompt" | ssh claude-code \
        "claude -p $model_flag --permission-mode bypassPermissions" 2>&1) || rc=$?
      ;;
  esac

  echo "$output"
  return $rc
}

# True when the output carries the promise tag on a line of its own. A tag
# merely mentioned inside a sentence is not a signal. ANSI colours, code-fence
# backticks, emphasis marks and surrounding whitespace are ignored.
# grep reads the whole input (no -q) so pipefail never sees a SIGPIPE.
has_promise() {
  printf '%s\n' "$1" \
    | sed -e 's/\x1b\[[0-9;]*[A-Za-z]//g' -e 's/\r$//' \
          -e 's/^[[:space:]`*]*//' -e 's/[[:space:]`*]*$//' \
    | grep -xF "<promise>$2</promise>" >/dev/null
}

init_beads() {
  if [[ "$USE_BEADS" != "true" ]]; then
    return 0
  fi

  # The beads container auto-initializes the database on start (with git-safe
  # flags). Never run `bd init` here — it can touch the project's git state.
  if [[ ! -d ".beads" ]]; then
    echo -e "${B}Beads not initialized — run 'ddev restart' to initialize it${R}"
  fi
}

# Loads PENDING_TASKS / PENDING_COUNT from `bd ready`. A failing bd (SSH or
# Beads down) is NOT "no tasks": it returns 1 so the caller retries, and aborts
# the run after MAX_CONSECUTIVE_FAILURES failures in a row.
# Usage: until refresh_pending_tasks; do sleep 2; done
BD_FAILURES=0
refresh_pending_tasks() {
  if [[ "$USE_BEADS" != "true" ]]; then
    PENDING_TASKS="[]"
    PENDING_COUNT=0
    return 0
  fi

  local out
  if out=$(bd ready --json 2>/dev/null); then
    BD_FAILURES=0
    # bd succeeded: anything that is not a JSON array means "nothing ready"
    if ! echo "$out" | jq -e 'type == "array"' >/dev/null 2>&1; then
      out="[]"
    fi
    PENDING_TASKS="$out"
    PENDING_COUNT=$(echo "$out" | jq 'length')
    return 0
  fi

  BD_FAILURES=$((BD_FAILURES + 1))
  echo -e "${Y}Warning: 'bd ready' failed (${BD_FAILURES}/${MAX_CONSECUTIVE_FAILURES}) - is the beads container reachable?${R}"
  if [[ "$BD_FAILURES" -ge "$MAX_CONSECUTIVE_FAILURES" ]]; then
    show_summary "ERROR: BEADS UNREACHABLE" "${iteration:-0}" "$RD" "${TASKS_COMPLETED:-N/A}"
    exit 1
  fi
  return 1
}

# --all: bd list leaves closed issues out by default
count_closed_tasks() {
  bd list --all --json 2>/dev/null | jq '[.[] | select(.status == "closed")] | length' 2>/dev/null || echo "0"
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

# Verify the target AI container is reachable via SSH
case "$BACKEND" in
  opencode)
    if ! ssh -o ConnectTimeout=5 opencode true &>/dev/null; then
      echo -e "${RD}Error: OpenCode container is not reachable via SSH (host: opencode).${R}"
      echo -e "${Y}Install it first: ddev add-on get trebormc/ddev-opencode && ddev restart${R}"
      exit 1
    fi
    ;;
  claude)
    if ! ssh -o ConnectTimeout=5 claude-code true &>/dev/null; then
      echo -e "${RD}Error: Claude Code container is not reachable via SSH (host: claude-code).${R}"
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
iteration=0
AI_FAILURES=0
PLANNING_ATTEMPTS=0
TASK_ID=""
declare -A TASK_ATTEMPTS=()
SKIPPED_IDS="[]"   # JSON array of task ids set aside after MAX_TASK_ATTEMPTS

if [[ "$USE_BEADS" == "true" ]]; then
  until refresh_pending_tasks; do sleep 2; done

  if [[ "$PENDING_COUNT" -eq 0 ]]; then
    # Check if there's any task history (closed tasks)
    ALL_TASKS=$(bd list --all --json 2>/dev/null || echo "[]")
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

while true; do
  iteration=$((iteration + 1))

  # Check max iterations
  if [[ "$iteration" -gt "$MAX_ITERATIONS" ]]; then
    # Update task count before exiting
    if [[ "$USE_BEADS" == "true" ]]; then
      ALL_TASKS=$(bd list --all --json 2>/dev/null || echo "[]")
      TASKS_COMPLETED=$(echo "$ALL_TASKS" | jq '[.[] | select(.status == "closed")] | length' 2>/dev/null || echo "0")
    fi
    show_summary "MAX ITERATIONS REACHED" "$((iteration - 1))" "$Y" "$TASKS_COMPLETED"
    exit 2
  fi

  # ==========================================================================
  # Get current state (Beads mode)
  # ==========================================================================

  if [[ "$USE_BEADS" == "true" ]]; then
    until refresh_pending_tasks; do sleep 2; done

    if [[ "$PHASE" == "execution" ]]; then
      # Pick the first ready task that has not been set aside. A task that is
      # still open after MAX_TASK_ATTEMPTS iterations is marked blocked and
      # skipped, so one stuck task cannot burn the whole iteration budget.
      while true; do
        CURRENT_TASK=$(echo "$PENDING_TASKS" | jq -c --argjson skip "$SKIPPED_IDS" \
          '[.[] | select(.id as $id | $skip | index($id) | not)] | .[0] // empty')
        TASK_ID=$(echo "$CURRENT_TASK" | jq -r '.id // empty' 2>/dev/null || true)
        [[ -z "$TASK_ID" ]] && break
        if [[ "${TASK_ATTEMPTS[$TASK_ID]:-0}" -lt "$MAX_TASK_ATTEMPTS" ]]; then
          break
        fi
        echo -e "${Y}Task $TASK_ID is still open after ${MAX_TASK_ATTEMPTS} attempts - marking it blocked and moving on.${R}"
        bd update "$TASK_ID" --status blocked \
          --notes "Ralph: not closed after ${MAX_TASK_ATTEMPTS} attempts, needs a human" >/dev/null 2>&1 || true
        SKIPPED_IDS=$(echo "$SKIPPED_IDS" | jq -c --arg id "$TASK_ID" '. + [$id]')
      done

      # No workable task left: done, or stopped on blocked tasks
      if [[ -z "$TASK_ID" ]]; then
        TASKS_COMPLETED=$(count_closed_tasks)
        SKIPPED_COUNT=$(echo "$SKIPPED_IDS" | jq 'length')
        if [[ "$SKIPPED_COUNT" -gt 0 ]]; then
          echo -e "${RD}Tasks set aside after ${MAX_TASK_ATTEMPTS} attempts: $(echo "$SKIPPED_IDS" | jq -r 'join(", ")')${R}"
          show_summary "STOPPED: $SKIPPED_COUNT TASK(S) BLOCKED" "$((iteration - 1))" "$RD" "$TASKS_COMPLETED"
          exit 1
        fi
        show_summary "ALL TASKS COMPLETED" "$((iteration - 1))" "$GR" "$TASKS_COMPLETED"
        exit 0
      fi
      TASK_ATTEMPTS[$TASK_ID]=$(( ${TASK_ATTEMPTS[$TASK_ID]:-0} + 1 ))
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

When you have created ALL necessary tasks, output this tag on a line by itself
(nothing else on that line; the loop ignores a tag written inside a sentence):
\`\`\`
<promise>PLANNING_COMPLETE</promise>
\`\`\`

Do NOT start working on tasks yet. Only create the task list."

  else
    # ========================================================================
    # EXECUTION PHASE PROMPT
    # ========================================================================

    if [[ "$USE_BEADS" == "true" ]]; then
      # CURRENT_TASK / TASK_ID: highest priority workable task, selected above
      TASK_TITLE=$(echo "$CURRENT_TASK" | jq -r '.title // empty' 2>/dev/null || true)
      TASK_PRIORITY=$(echo "$CURRENT_TASK" | jq -r '.priority // empty' 2>/dev/null || true)

      PROMPT="[RALPH LOOP - Iteration $iteration of $MAX_ITERATIONS]

## Current Task

**ID:** $TASK_ID
**Title:** $TASK_TITLE
**Priority:** P$TASK_PRIORITY
**Attempt:** ${TASK_ATTEMPTS[$TASK_ID]} of $MAX_TASK_ATTEMPTS (after that the loop marks the task blocked and moves on)

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
- If you **encounter an unrecoverable error**, output this tag on a line by itself
  (it stops the whole run; never write the tag for any other reason):
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

When you have COMPLETED ALL tasks described above, you MUST output this tag on a
line by itself (the loop ignores a tag written inside a sentence):
\`\`\`
<promise>COMPLETE</promise>
\`\`\`

If you encounter an unrecoverable error that prevents completion, output on a line by itself:
\`\`\`
<promise>ERROR</promise>
\`\`\`

Do NOT continue working after outputting a completion signal."
    fi
  fi

  # ==========================================================================
  # Run AI Tool
  # ==========================================================================

  AI_RC=0
  OUTPUT=$(run_ai_tool "$PROMPT") || AI_RC=$?

  echo "$OUTPUT"

  # A backend that keeps failing (auth error, wrong model, SSH down) would
  # otherwise spin through every iteration doing nothing.
  if [[ "$AI_RC" -ne 0 ]]; then
    AI_FAILURES=$((AI_FAILURES + 1))
    echo ""
    echo -e "${Y}Warning: $BACKEND backend exited with code $AI_RC (${AI_FAILURES}/${MAX_CONSECUTIVE_FAILURES} consecutive failures)${R}"
    if [[ "$AI_FAILURES" -ge "$MAX_CONSECUTIVE_FAILURES" ]]; then
      if [[ "$USE_BEADS" == "true" ]]; then
        TASKS_COMPLETED=$(count_closed_tasks)
      fi
      show_summary "ERROR: BACKEND FAILED ${AI_FAILURES} TIMES IN A ROW" "$iteration" "$RD" "$TASKS_COMPLETED"
      exit 1
    fi
  else
    AI_FAILURES=0
  fi

  ITER_TIME=$(($(date +%s) - ITER_START))
  echo ""
  echo -e "  ${B}Iteration completed in ${Y}$(format_time $ITER_TIME)${R}"

  # ==========================================================================
  # Check signals and state
  # ==========================================================================

  # Check for planning completion. Planning ends on the promise tag OR as soon
  # as tasks exist: re-running the planning prompt on top of an existing plan
  # only creates duplicates. (Planning only happens in Beads mode.)
  if [[ "$PHASE" == "planning" ]] && ! has_promise "$OUTPUT" "ERROR"; then
    PLANNING_ATTEMPTS=$((PLANNING_ATTEMPTS + 1))
    PLANNING_SIGNALLED=false
    if has_promise "$OUTPUT" "PLANNING_COMPLETE"; then
      PLANNING_SIGNALLED=true
    fi
    until refresh_pending_tasks; do sleep 2; done

    if [[ "$PENDING_COUNT" -gt 0 ]]; then
      echo ""
      if [[ "$PLANNING_SIGNALLED" == "true" ]]; then
        echo -e "${GR}Planning complete!${R} Switching to execution phase."
      else
        echo -e "${Y}No PLANNING_COMPLETE signal, but tasks exist.${R} Switching to execution phase instead of planning again."
      fi
      PHASE="execution"
      echo -e "Created ${Y}$PENDING_COUNT${R} tasks:"
      echo -e "${DIM}$(echo "$PENDING_TASKS" | jq -r '.[] | "  - [P\(.priority)] \(.title)"' 2>/dev/null || true)${R}"

      echo ""
      echo -e "${Y}Starting execution in ${DELAY_SECONDS}s...${R}"
      sleep $DELAY_SECONDS
      continue
    fi

    # No ready task: a plan that signals completion with nothing to do is an
    # error, not a finished project.
    if [[ "$PLANNING_SIGNALLED" == "true" ]]; then
      echo ""
      echo -e "${RD}Planning signalled completion but 'bd ready' is empty - no tasks were created.${R}"
      show_summary "ERROR: PLANNING CREATED NO TASKS" "$iteration" "$RD" "0"
      exit 1
    fi
    if [[ "$PLANNING_ATTEMPTS" -ge "$MAX_PLANNING_ATTEMPTS" ]]; then
      echo ""
      echo -e "${RD}Planning produced no tasks in ${PLANNING_ATTEMPTS} attempts.${R}"
      show_summary "ERROR: PLANNING CREATED NO TASKS" "$iteration" "$RD" "0"
      exit 1
    fi
  fi

  # Check for error signal
  if has_promise "$OUTPUT" "ERROR"; then
    if [[ "$USE_BEADS" == "true" ]]; then
      TASKS_COMPLETED=$(count_closed_tasks)
    fi
    show_summary "ERROR" "$iteration" "$RD" "$TASKS_COMPLETED"
    exit 1
  fi

  # Check for legacy COMPLETE signal (only in non-Beads mode)
  if [[ "$USE_BEADS" != "true" ]]; then
    if has_promise "$OUTPUT" "COMPLETE"; then
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
