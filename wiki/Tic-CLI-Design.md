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
