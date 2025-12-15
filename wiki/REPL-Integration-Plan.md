# REPL Integration Plan: Merging Chatarang into Dartantic CLI

This document outlines the plan to integrate interactive REPL capabilities from chatarang into the dartantic CLI with MCP-only tools.

## Overview

**Goal**: Add an interactive REPL mode to the dartantic CLI that:
1. Uses only MCP server tools from the selected agent (no built-in tools)
2. Provides slash commands that mirror CLI functionality
3. Maintains conversation history within a session
4. Streams responses in real-time

## Current State

### Dartantic CLI (`samples/dartantic_cli/`)
- Single-turn batch execution
- Commands: `chat`, `generate`, `embed`, `models`
- MCP tool integration via `McpToolCollector`
- Settings-based agent configuration
- REPL explicitly listed as "Non-Goal v1" in CLI-Spec.md

### Chatarang (`samples/chatarang/`)
- Full REPL using `cli_repl` package
- Slash commands: `/exit`, `/quit`, `/model`, `/models`, `/tools`, `/messages`, `/clear`, `/help`
- Built-in tools (weather, location, time, surf-web)
- Conversation history with `HistoryEntry` tracking
- Multi-provider model switching

## Implementation Plan

### Phase 1: Add REPL Command to CLI

#### 1.1 Create `ReplCommand` class

**File**: `lib/src/commands/repl_command.dart`

- Extends `DartanticCommand` like other commands
- Entry point for `dartantic repl` or `dartantic` (when detecting interactive stdin)
- Reuses existing infrastructure:
  - `SettingsLoader` for agent resolution
  - `McpToolCollector` for MCP tools
  - `PromptProcessor` for `@file` attachments in prompts

#### 1.2 Add `cli_repl` dependency

**File**: `pubspec.yaml`

Add:
```yaml
dependencies:
  cli_repl: ^0.2.3
```

#### 1.3 Register command in runner

**File**: `lib/src/runner.dart`

- Add `ReplCommand` to command list
- Optionally: auto-detect interactive mode when no args provided and stdin is TTY

### Phase 2: Implement REPL Infrastructure

#### 2.1 Create `ReplSession` class

**File**: `lib/src/repl/repl_session.dart`

Responsibilities:
- Manage the interactive loop using `cli_repl`
- Hold conversation history (`List<HistoryEntry>`)
- Hold current Agent instance
- Handle MCP tool lifecycle (collect on start, dispose on exit)
- Stream responses to stdout

Key state:
```
- Agent agent
- List<HistoryEntry> history
- McpToolCollector toolCollector
- List<Tool> tools
- Settings settings
- String currentAgentName
```

#### 2.2 Create `HistoryEntry` class

**File**: `lib/src/repl/history_entry.dart`

Track messages with metadata:
```
- ChatMessage message
- String modelName (for model messages only)
```

#### 2.3 Create `ReplCommandHandler` class

**File**: `lib/src/repl/repl_command_handler.dart`

Handle slash commands within the REPL session. Commands map to CLI functionality:

| Slash Command | Description | CLI Equivalent |
|---------------|-------------|----------------|
| `/exit`, `/quit` | Exit REPL | N/A |
| `/help` | Show available commands | `dartantic --help` |
| `/model [name]` | View/switch current agent | `-a` flag |
| `/models [filter]` | List available models | `dartantic models` |
| `/tools` | Show available MCP tools | N/A (new) |
| `/messages` | Display conversation history | N/A (new) |
| `/clear` | Clear history, keep agent | N/A (new) |
| `/system [prompt]` | View/set system prompt | Agent settings |
| `/attach <file>` | Attach file for next message | `@file` syntax |
| `/verbose` | Toggle verbose mode | `-v` flag |
| `/thinking` | Toggle thinking display | `--no-thinking` flag |

#### 2.4 Handle `@file` syntax in REPL prompts

Reuse `PromptProcessor` from existing CLI to handle:
- `@filename` attachments
- `.prompt` template files with variable substitution

### Phase 3: MCP Tool Integration

#### 3.1 Tool collection on agent switch

When switching agents via `/model`:
1. Dispose existing MCP clients
2. Look up new agent in settings
3. Collect MCP tools from new agent's `mcp_servers`
4. Recreate Agent with new tools

#### 3.2 Tool display with `/tools`

Show tools collected from MCP servers:
- Tool name
- Description
- Input schema (abbreviated)

Unlike chatarang, no built-in tools will be added.

### Phase 4: Agent Resolution & Model Switching

#### 4.1 Agent resolution flow

Same as CLI batch mode:
1. CLI `-a` flag → agent name
2. Env var `DARTANTIC_AGENT`
3. Settings `default_agent`
4. Default: `'google'`

Then resolve:
- If agent name in `settings.agents` → use agent config
- Otherwise → treat as model string

#### 4.2 Model switching in REPL

`/model <name>` command:
1. Resolve new agent (same flow as above)
2. Preserve conversation history
3. Reinitialize MCP tools for new agent
4. Update system prompt if agent has one

### Phase 5: Streaming & Output

#### 5.1 Response streaming

Reuse streaming logic from `ChatCommand`:
- Stream chunks to stdout
- Handle thinking output with `[Thinking]...[/Thinking]`
- Collect messages for history

#### 5.2 Color scheme

Match existing CLI colors:
- Prompt: Blue (`\x1B[94m`)
- Model name: Yellow (`\x1B[93m`)
- Tool calls: Magenta (`\x1B[95m`)
- Tool results: Cyan (`\x1B[96m`)
- System: Red (`\x1B[91m`)
- Thinking: Dim (`\x1b[2m`)
- Respect `--no-color` flag

### Phase 6: Update Specification

#### 6.1 Update `wiki/CLI-Spec.md`

- Move REPL from "Non-Goals" to main documentation
- Add REPL command reference
- Add slash command documentation
- Add test scenarios for REPL mode

## File Structure

```
samples/dartantic_cli/
├── lib/src/
│   ├── commands/
│   │   ├── repl_command.dart        # New: REPL entry point command
│   │   └── ... (existing)
│   ├── repl/                        # New: REPL module
│   │   ├── repl_session.dart        # Main REPL loop and state
│   │   ├── repl_command_handler.dart # Slash command handling
│   │   └── history_entry.dart       # History entry model
│   └── ... (existing)
└── pubspec.yaml                     # Add cli_repl dependency
```

## Key Differences from Chatarang

| Aspect | Chatarang | Dartantic CLI REPL |
|--------|-----------|-------------------|
| Tools | Built-in (weather, etc.) | MCP servers only |
| Agent config | Model string only | Settings file + model strings |
| System prompt | Hardcoded | From agent settings |
| File attachments | Not supported | `@file` syntax |
| Thinking display | Not supported | Supported |
| Structured output | Not supported | `--output-schema` |
| Model discovery | All providers at startup | Per-agent via `/models` |

## Test Scenarios

### REPL-specific scenarios to add:

```bash
# SR-001: Start REPL with default agent
dartantic repl

# SR-002: Start REPL with specific agent
dartantic repl -a coder

# SR-003: Model switching in REPL
/model anthropic

# SR-004: List models in REPL
/models google

# SR-005: View available tools
/tools

# SR-006: View conversation history
/messages

# SR-007: Clear history
/clear

# SR-008: File attachment in REPL
@document.txt What is this about?

# SR-009: Exit REPL
/exit

# SR-010: Help command
/help

# SR-011: Toggle verbose
/verbose

# SR-012: View/set system prompt
/system
/system You are a helpful assistant.
```

## Migration Notes

- Chatarang can be deprecated after REPL is integrated into CLI
- Users migrate by using `dartantic repl` instead of `chatarang`
- Configure agents in `~/.dartantic/settings.yaml` instead of editing code
- MCP servers replace built-in tools for extensibility

## Implementation Order

1. **Phase 1**: Add basic `ReplCommand` that starts an interactive loop
2. **Phase 2**: Implement `ReplSession` with basic chat (no slash commands)
3. **Phase 3**: Add MCP tool collection (reuse `McpToolCollector`)
4. **Phase 4**: Implement `ReplCommandHandler` with slash commands
5. **Phase 5**: Add streaming and color output
6. **Phase 6**: Update documentation and add tests
