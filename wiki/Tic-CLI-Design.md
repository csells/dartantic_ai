# Tic CLI Design

Interactive CLI for the Dartantic AI framework with multi-mode REPL, vector database management, and code generation.

**Name**: `tic` (Dartantic → Agentic → nervous tic)

## Overview

Tic unifies batch and interactive workflows across three modes:
- **Chat**: LLM conversation with optional vector DB context
- **Generate**: LLM media generation (images, PDFs, etc.)
- **Embed**: Vector database (vault) management and raw search

## CLI Entry Points

Commands without required args enter REPL mode; with args they execute batch operations.

```
tic                           # REPL in chat mode (default)
tic chat                      # REPL in chat mode
tic chat -p "hello"           # batch: single chat

tic embed                     # REPL in embed mode
tic embed -db codebase        # REPL in embed mode with vault
tic embed sync -db codebase   # batch: sync vault

tic generate                  # REPL in generate mode
tic generate -p "..." --mime image/png  # batch: generate media
```

## Modes

### Chat Mode (default)
- Prompts sent to LLM for conversation
- Conversation history maintained
- Vector DB available as local tool (if configured)
- MCP tools available (from agent settings)

```
[chat] You: Hello, how are you?
[chat] You: What files mention authentication?  # LLM uses search tool
```

### Generate Mode
- Prompts sent to LLM for media generation
- Output saved to files in output directory
- Vector DB available as context tool
- Need to specify/set MIME type

```
[generate] You: A sunset over mountains
[generate] You: /mime application/pdf
[generate] You: Create a report about our codebase
```

### Embed Mode
- Vault management (no LLM interaction)
- Prompts are raw vector similarity searches
- Manage, sync, and explore indexed content

```
[embed] You: authentication              # raw vector search
[embed] You: /status                     # vault info
[embed] You: /sync                       # refresh embeddings
[embed] You: /files                      # list indexed files
```

## Mode Switching

**Mode switch** (no args): Changes current mode
```
[chat] You: /embed              # switch to embed mode
[embed] You: /generate          # switch to generate mode
[generate] You: /chat           # switch to chat mode
```

**One-shot** (with args): Execute in that mode, stay in current mode
```
[chat] You: /embed @doc.txt           # one-shot: embed file, stay in chat
[chat] You: /embed machine learning   # one-shot: raw search, stay in chat
[chat] You: /generate A sunset        # one-shot: generate, stay in chat
```

## Slash Commands

### Universal Commands
| Command | Description |
|---------|-------------|
| `/help` | Show available commands |
| `/exit`, `/quit` | Exit REPL |
| `/chat [prompt]` | Switch to chat mode, or one-shot chat |
| `/embed [query]` | Switch to embed mode, or one-shot search |
| `/generate [prompt]` | Switch to generate mode, or one-shot generate |

### Agent & Model Commands
| Command | Description |
|---------|-------------|
| `/agent` | Show current agent |
| `/agent <name>` | Switch agent |
| `/model` | Show current model (for current mode) |
| `/model <name>` | Switch model (for current mode) |
| `/models [filter]` | List models (for current mode) |

### Vault Commands (embed mode or universal)
| Command | Description |
|---------|-------------|
| `/vault` | Show current vault |
| `/vault <name>` | Switch vault |
| `/vaults` | List available vaults |
| `/sync` | Sync vault with filesystem |
| `/status` | Show vault status (files, stale, etc.) |
| `/files` | List indexed files/chunks |

### Generate Mode Commands
| Command | Description |
|---------|-------------|
| `/mime` | Show current MIME type |
| `/mime <type>` | Set MIME type for generation |

### History Commands
| Command | Description |
|---------|-------------|
| `/history` | Show session summary |
| `/history save <name>` | Save session |
| `/history load <name>` | Load session |
| `/history list` | List saved sessions |
| `/history clear` | Clear current session |
| `/history delete <name>` | Delete saved session |

### Code Export
| Command | Description |
|---------|-------------|
| `/code` | Print Dart code for session to stdout |
| `/code <file.dart>` | Save Dart code to file |

### Other
| Command | Description |
|---------|-------------|
| `/system` | Show system prompt |
| `/system <text>` | Set system prompt |
| `/verbose` | Toggle verbose output |
| `/thinking` | Toggle thinking display |
| `/tools` | Show available tools (MCP + search) |
| `/messages` | Show conversation history |
| `/clear` | Clear conversation (alias for `/history clear`) |

## Vector Database (Vault) System

### Concept
A **vault** is a named collection of:
- Source files/folders to index
- Output location for cached embeddings
- Embedding model configuration

Vaults sync automatically on file changes, minimizing re-embedding costs.

### Settings Configuration
```yaml
# ~/.tic/settings.yaml

vaults:
  codebase:
    sources:
      - ./src
      - ./lib
    output: ./.tic/vaults/codebase
    model: openai:text-embedding-3-small
    chunk_size: 512
    chunk_overlap: 100

  docs:
    sources:
      - ./wiki
      - ./README.md
    output: ./.tic/vaults/docs

agents:
  coder:
    model: anthropic:claude-sonnet-4-20250514
    vaults: [codebase, docs]  # vaults available to this agent
    mcp_servers:
      - name: filesystem
        command: npx
        args: ["-y", "@anthropic/mcp-server-filesystem", "."]
```

### LLM Integration
When a vault is active in chat/generate mode:
- A local `search_vault` tool is automatically available
- LLM can search the vault for relevant context
- Works alongside MCP tools

```
[chat] You: What authentication methods does this codebase support?
# LLM calls search_vault("authentication") internally
# Gets relevant chunks as context
# Responds with grounded answer
```

## History & Sessions

Sessions are transient by default. Use `/history save` to persist.

**Storage**: `~/.tic/sessions/<name>.json`

**Session contains**:
- Mode transitions
- Conversation history (all modes)
- Active vault/agent at each point
- Model switches

## Code Export

The `/code` command generates Dart code that recreates the session:

```dart
import 'package:dartantic_ai/dartantic_ai.dart';

void main() async {
  // Agent setup
  final agent = Agent('anthropic:claude-sonnet-4-20250514');

  // Conversation
  var response = await agent.send('Hello, how are you?');
  print(response.text);

  response = await agent.send(
    'Tell me about Dart',
    history: response.messages,
  );
  print(response.text);

  // Model switch
  final agent2 = Agent('openai:gpt-4o');
  response = await agent2.send(
    'Summarize our conversation',
    history: response.messages,
  );

  // Embeddings
  final embeddings = await agent.embedDocuments(['text to embed']);

  // Media generation
  final media = await agent.generate(
    'A sunset over mountains',
    mimeTypes: ['image/png'],
  );
  // ... save media to file
}
```

## File Attachments

Use `@filename` syntax in prompts to attach files:

```
[chat] You: Summarize this: @document.pdf
[chat] You: Compare @file1.txt and @file2.txt
[embed] You: @newdoc.txt    # would add to vault? or just embed?
```

## Configuration

### Settings File Location
`~/.tic/settings.yaml`

### Full Settings Schema
```yaml
# Default agent when not specified
default_agent: coder

# Default vault when not specified
default_vault: codebase

# Global defaults
thinking: true
verbose: false

# Vault definitions
vaults:
  <vault-name>:
    sources: [<paths>]
    output: <path>
    model: <embedding-model-string>
    chunk_size: 512
    chunk_overlap: 100

# Agent definitions
agents:
  <agent-name>:
    model: <model-string>
    system: <system-prompt>
    thinking: true|false
    vaults: [<vault-names>]
    mcp_servers:
      - name: <server-name>
        url: <https://...>
        headers: {...}
      - name: <server-name>
        command: <executable>
        args: [...]
        environment: {...}
```

### Sessions Location
`~/.tic/sessions/`

### Vault Cache Location
Configurable per-vault via `output` field, or defaults to `~/.tic/vaults/<name>/`

## CLI Arguments

### Global Options
```
-a, --agent <name>      Agent name or model string
-s, --settings <path>   Settings file path
-d, --cwd <path>        Working directory
-o, --output-dir <path> Output directory for generated files
-v, --verbose           Show token usage
--no-thinking           Disable thinking display
--no-color              Disable colored output
--db, --vault <name>    Active vault
--version               Show version
-h, --help              Show help
```

### Chat Options
```
-p, --prompt <text>     Prompt (batch mode)
--output-schema <json>  Structured output schema
-t, --temperature <n>   Model temperature
```

### Generate Options
```
-p, --prompt <text>     Prompt (batch mode)
--mime <type>           MIME type(s) to generate
```

### Embed Options
```
--db, --vault <name>    Vault to operate on
```

## Example Workflows

### Interactive Code Exploration
```
$ tic -a coder --db codebase
[chat] You: How does authentication work in this codebase?
[chat] You: Show me the login flow
[chat] You: /embed                    # switch to embed mode
[embed] You: authentication handler   # raw search
[embed] You: /chat                    # back to chat
[chat] You: Refactor the auth to use JWT
[chat] You: /code auth_refactor.dart  # export session as code
```

### Batch Embedding Pipeline
```
$ tic embed sync --db codebase        # sync vault
$ tic embed sync --db docs            # sync another vault
$ tic -a coder --db codebase -p "Summarize the architecture"
```

### Media Generation Session
```
$ tic generate
[generate] You: /mime image/png
[generate] You: A logo for an AI company
[generate] You: Make it more minimalist
[generate] You: /mime application/pdf
[generate] You: Create a brand guidelines document
```

## Open Questions

### 1. `/embed` One-Shot Ambiguity

`/embed @doc.txt` (add to vault) vs `/embed query` (search) are different operations with same syntax.

**Options**:
- **A**: Separate commands: `/search <query>` for search, `/index @file` for adding to vault. Keep `/embed` for mode switching only.
- **B**: Detect `@` prefix to distinguish operations.
- **C**: `/embed` always searches; use `/vault add @file` to index.

---

### 2. Generate Mode Feature Parity

Generate mode lacks features that chat has:
- Temperature
- System prompt (for style guidance)
- File attachments (reference images)
- Thinking display
- Multi-turn iteration

**Questions**:
- Should generate support temperature? (`-t` batch, `/temperature` REPL)
- Should generate have system prompts? (e.g., "Always use minimalist style")
- Should generate support `@file` attachments? (e.g., `@sketch.png` as reference)
- Does multi-turn generation make sense? ("Make it more blue")

---

### 3. Missing REPL Commands for Batch Options

Batch has options that can't be changed in REPL:
- Temperature (`-t`)
- Output schema (`--output-schema`)
- Output directory (`-o`)

**Proposed commands**:
```
/temperature [n]          # show or set (chat/generate)
/schema [json|@file]      # show or set output schema (chat)
/output [dir]             # show or set output directory (generate)
```

---

### 4. `/model` vs `/agent` Relationship

Agents have models, but `/model` exists separately. Confusion about what `/model` overrides.

**Options**:
- **A**: Remove `/model`. Only `/agent` exists. To use a raw model, use `-a model:string` syntax which creates an anonymous agent.
- **B**: `/model` temporarily overrides the current agent's model for the current mode.
- **C**: Keep both but clarify: `/agent` switches config bundle, `/model` switches just the LLM.

---

### 5. Batch Embed Operations

Only `sync` shown for batch embed. Missing operations:

**Proposed batch commands**:
```
tic embed sync --db <vault>              # sync vault
tic embed search <query> --db <vault>    # search vault
tic embed status --db <vault>            # show vault status
tic embed create --db <name> --sources <paths> [--output <path>]
tic embed delete --db <vault>            # delete vault
tic embed files --db <vault>             # list indexed files
```

---

### 6. Vault Search in Generate Mode

Doc claims vault available as tool in generate, but generation typically doesn't do tool calls.

**Options**:
- **A**: Pre-flight injection via `/context <query>` command that searches vault and injects into next prompt.
- **B**: Remove the claim if model doesn't support tools during generation.
- **C**: For models that support it, allow tool use during generation.

---

### 7. `/clear` Meaning Per Mode

`/clear` in embed mode is meaningless (no conversation) or dangerous (clear vault?).

**Options**:
- **A**: Mode-specific behavior: chat=conversation, generate=generation history, embed=search history
- **B**: Disable `/clear` in embed mode
- **C**: `/clear` always means conversation/prompt history, never vault data

---

### 8. File Attachment in Embed Mode

What does `@file` mean in embed mode?

**Options**:
- **A**: `@file` in embed mode = add file to vault and index it
- **B**: `@file` in embed mode = error ("use /index @file instead")
- **C**: `@file` in embed mode = search contents of file (not index it)

---

### 9. Multi-Vault Handling

Agents can have multiple vaults but interaction unclear.

**Questions**:
- Does `search_vault` tool search all agent vaults or just active one?
- Should tool accept vault name parameter?
- What does `/vault` show/switch when agent has multiple?

**Proposed settings**:
```yaml
agents:
  coder:
    vaults: [codebase, docs]  # all available
    default_vault: codebase   # active by default
```

---

### 10. Missing `/config` Command

No unified view of current state.

**Proposed output**:
```
[chat] You: /config
Agent: coder (anthropic:claude-sonnet-4-20250514)
Mode: chat
Vault: codebase (3,247 chunks, synced 2 min ago)
MCP: filesystem (3 tools)
Verbose: off
Thinking: on
Temperature: 0.7
```

---

### 11. Embed Search Output Format

What format for raw search results?

**Options**:
- **A**: Human-readable table by default, `/format json` to switch
- **B**: JSON by default (machine-friendly)
- **C**: Human-readable always in REPL, JSON in batch

**Proposed REPL output**:
```
[embed] You: authentication
Score  File                      Preview
0.89   src/auth/handler.dart     "The authentication handler validates..."
0.84   src/auth/middleware.dart  "JWT tokens are verified in..."
```

---

### 12. Batch Mode Default Vault

If no `--db` specified in batch mode, what happens?

**Options**:
- **A**: Use `default_vault` from settings, error if none
- **B**: No vault (tool not available), proceed without
- **C**: Error always if vault-dependent operation

---

### 13. Generate MIME Default

Must specify MIME every time?

**Options**:
- **A**: Default to `image/png` (most common)
- **B**: No default, require explicit
- **C**: Remember last MIME type in session

---

### 14. Command Aliases

Should common commands have short aliases?

**Proposed**:
```
/q  → /quit
/h  → /help
/v  → /vault (or /verbose?)
/s  → /search
/?  → /help
```

**Conflict**: `/v` could be `/vault` or `/verbose`. Worth having aliases?

---

### 15. Feature Completeness Matrix

Current state showing gaps:

| Feature | Chat Batch | Chat REPL | Gen Batch | Gen REPL | Embed Batch | Embed REPL |
|---------|:----------:|:---------:|:---------:|:--------:|:-----------:|:----------:|
| Prompt | `-p` | direct | `-p` | direct | N/A | direct |
| Agent | `-a` | `/agent` | `-a` | `/agent` | `-a` | `/agent` |
| Vault | `--db` | `/vault` | `--db` | `/vault` | `--db` | `/vault` |
| Temperature | `-t` | ❓ | ❓ | ❓ | N/A | N/A |
| Output Schema | `--output-schema` | ❓ | N/A | N/A | N/A | N/A |
| MIME | N/A | N/A | `--mime` | `/mime` | N/A | N/A |
| System | config | `/system` | ❓ | ❓ | N/A | N/A |
| Thinking | `--no-thinking` | `/thinking` | ❓ | ❓ | N/A | N/A |
| Verbose | `-v` | `/verbose` | `-v` | `/verbose` | `-v` | `/verbose` |
| Output Dir | `-o` | ❓ | `-o` | ❓ | N/A | N/A |
| File Attach | `@file` | `@file` | ❓ | ❓ | ❓ | ❓ |
| Sync | N/A | N/A | N/A | N/A | `sync` | `/sync` |
| Search | tool | tool | ❓ | ❓ | ❓ | direct |
| Status | N/A | N/A | N/A | N/A | ❓ | `/status` |

---

## Implementation Notes

### Dependencies
- `cli_repl` for interactive loop
- `ragamuffin` patterns for vault management
- SQLite for embedding cache (via ragamuffin approach)

### Key Components
- `TicCommandRunner` - CLI entry point and routing
- `ReplSession` - Interactive loop management
- `ModeHandler` - Mode-specific prompt handling
- `VaultManager` - Embedding cache and sync
- `SessionManager` - History save/load
- `CodeExporter` - Dart code generation

### Migration from dartantic_cli
- Rename package to `tic`
- Move settings to `~/.tic/`
- Integrate ragamuffin vault system
- Add REPL infrastructure
