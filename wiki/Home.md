This document provides a comprehensive overview of the dartantic_ai package architecture and points to detailed specifications for each major system.

## System Purpose

The dartantic_ai package provides a unified interface to 8 built-in LLM providers through a single import (extensible via `Agent.providerFactories`), implementing a clean abstraction layer that supports:
- Chat conversations with streaming
- Text embeddings generation
- Tool/function calling 
- Structured JSON output
- Multiple provider types (cloud APIs, local models)
- Provider-hosted capabilities (server-side tools) when available
- Model reasoning streams ("thinking") for compatible providers
- Comprehensive logging and debugging

## Core Architectural Principles

### 1. **Six-Layer Architecture**
The system is organized into six distinct layers, each with focused responsibilities:

```mermaid
graph TB
    subgraph "API Layer"
        A1[Agent - User Interface]
        A2[Public Contracts]
    end
    
    subgraph "Orchestration Layer"
        O1[StreamingOrchestrator]
        O2[ToolExecutor]
        O3[Business Logic]
    end
    
    subgraph "Provider Abstraction Layer"
        P1[Provider Interface]
        P2[ChatModel Interface]
        P3[EmbeddingsModel Interface]
        P4[ModelInfo]
    end
    
    subgraph "Provider Implementation Layer"
        I1[Concrete Providers]
        I2[Message Mappers]
        I3[Protocol Handlers]
    end
    
    subgraph "Infrastructure Layer"
        F1[RetryHttpClient]
        F2[LoggingOptions]
        F3[Exception Hierarchy]
        F4[Utilities]
    end
    
    subgraph "Protocol Layer"
        PR1[HTTP Clients]
        PR2[API Communication]
    end
    
    A1 --> O1
    O1 --> P2
    P1 --> I1
    I1 --> F1
    F1 --> PR1
    
    style A1 fill:#f9f,stroke:#333,stroke-width:2px
    style O1 fill:#bbf,stroke:#333,stroke-width:2px
    style P1 fill:#bfb,stroke:#333,stroke-width:2px
```

### 2. **Separation of Concerns**
- **Agent (API Layer)**: Thin coordination layer (56% size reduction from monolithic design)
- **Orchestration**: Complex workflow management extracted from Agent
- **Provider Abstraction**: Clean contracts independent of implementation
- **Implementation**: Provider-specific quirks isolated
- **Infrastructure**: Cross-cutting concerns centralized
- **Protocol**: Network communication separated from business logic

### 3. **Streaming-First Design**
- Built on streaming foundation with orchestrator abstraction
- Process entire model stream before making decisions
- Isolated streaming state per request
- Consistent behavior across providers

### 4. **Exception Transparency**
- Never suppress exceptions
- Errors bubble up with full context
- Structured exception hierarchy
- No defensive error hiding

### 5. **Resource Management**
- Direct model creation through providers
- Guaranteed cleanup via try/finally patterns
- Simple disposal with model.dispose()
- No hidden lifecycle management

## Complete Request Flow

The following diagram shows how a chat request with tool calls flows through all layers:

```mermaid
sequenceDiagram
    participant User
    participant Agent
    participant Orchestrator
    participant State as StreamingState
    participant Provider
    participant Model
    participant Executor as ToolExecutor
    participant API
    
    User->>Agent: send("What's the weather?")
    
    rect rgb(255, 230, 230)
        note over Agent: API Layer
        Agent->>Agent: Parse model string
        Agent->>Provider: Agent.createProvider()
        Agent->>Provider: createChatModel()
        Agent->>Orchestrator: Select orchestrator
    end
    
    rect rgb(230, 255, 230)
        note over Orchestrator: Orchestration Layer
        Agent->>State: Create StreamingState
        Agent->>Orchestrator: initialize(state)
        
        loop Until no more tools
            Orchestrator->>Model: sendStream(messages)
            Model->>API: HTTP request
            
            loop Stream chunks
                API-->>Model: Chunk
                Model-->>Orchestrator: ChatResult
                Orchestrator->>State: accumulate(chunk)
                Orchestrator-->>Agent: yield text
                Agent-->>User: Stream output
            end
            
            Orchestrator->>State: consolidate()
            
            alt Tool calls present
                Orchestrator->>Executor: executeBatch(tools)
                Executor-->>Orchestrator: results
                Orchestrator->>State: add results
            else No tools
                Orchestrator-->>Agent: done
            end
        end
        
        Orchestrator->>Orchestrator: finalize(state)
    end
    
    rect rgb(230, 230, 255)
        note over Model: Resource Cleanup
        Agent->>Model: dispose()
    end
```

## StreamingState Lifecycle

The StreamingState encapsulates all mutable state during streaming operations:

```mermaid
stateDiagram-v2
    [*] --> Created: new StreamingState()
    Created --> Initialized: orchestrator.initialize()
    
    Initialized --> Streaming: model.sendStream()
    
    state Streaming {
        [*] --> Accumulating
        Accumulating --> Accumulating: accumulate chunks
        Accumulating --> Consolidating: stream closes
        Consolidating --> CheckingTools
        
        CheckingTools --> ExecutingTools: tools found
        CheckingTools --> Complete: no tools
        
        ExecutingTools --> AddingResults
        AddingResults --> [*]: continue iteration
    }
    
    Streaming --> Finalized: all iterations done
    Finalized --> [*]: dispose
    
    note right of Accumulating
        State tracks:
        - conversationHistory
        - accumulatedMessage
        - toolMap
        - UX flags
    end note
```

## Tool Execution Flow

Tool detection, execution, and result integration:

```mermaid
flowchart TD
    A[Consolidated Message] --> B{Contains Tool Calls?}
    
    B -->|Yes| C[Extract ToolParts]
    B -->|No| Z[Complete]
    
    C --> D[Register Tool IDs]
    D --> E[ToolExecutor.executeBatch]
    
    E --> F[For each tool]
    F --> G{Tool exists?}
    
    G -->|Yes| H[Execute tool.invoke]
    G -->|No| I[Error result]
    
    H --> J{Success?}
    J -->|Yes| K[Success result]
    J -->|No| L[Error result]
    
    K --> M[Collect results]
    I --> M
    L --> M
    
    M --> N[Create ToolPart.result]
    N --> O[Add to conversation]
    O --> P[Continue streaming]
    
    style E fill:#f9f,stroke:#333,stroke-width:2px
    style H fill:#9f9,stroke:#333,stroke-width:2px
```

## Orchestration Component Interaction

How orchestration layer components collaborate:

```mermaid
graph LR
    subgraph "Orchestration Layer"
        O[StreamingOrchestrator]
        S[StreamingState]
        E[ToolExecutor]
        A[MessageAccumulator]
        
        O -->|manages| S
        O -->|delegates to| E
        S -->|contains| A
        S -->|provides tools to| E
        
        O -.->|1. initialize| S
        O -.->|2. accumulate via| A
        O -.->|3. execute via| E
        O -.->|4. finalize| S
    end
    
    style O fill:#bbf,stroke:#333,stroke-width:2px
    style S fill:#fff3e0,stroke:#333,stroke-width:2px
    style E fill:#f3e5f5,stroke:#333,stroke-width:2px
    style A fill:#fce4ec,stroke:#333,stroke-width:2px
```

## Major System Components

### 🏗️ **Orchestration Layer**
Coordinates business logic and streaming workflows. See [[Orchestration-Layer-Architecture]] for details.
- DefaultStreamingOrchestrator for standard workflows
- TypedOutputStreamingOrchestrator for structured JSON
- StreamingState for mutable state encapsulation
- ToolExecutor for centralized tool execution

### 🔧 **Unified Provider Architecture**
Single provider interface for both chat and embeddings. See [[Unified-Provider-Architecture]].
- Provider base class with capability declarations
- Factory methods for model creation
- Registry and discovery mechanisms

### 📝 **Model Configuration**
Flexible model string parsing and defaults. See [[Model-Configuration-Spec]].
- URI-based parsing: `provider?chat=model&embeddings=embed`
- Legacy formats supported: `provider:model`
- Provider default models

### 🔑 **Agent Configuration**
API key and base URL resolution. See [[Agent-Config-Spec]].
- Provider-level API key resolution
- Environment variable handling
- Cross-platform considerations

### 🌊 **Streaming & Tool Calls**
Provider-specific streaming patterns. See [[Streaming-Tool-Call-Architecture]].
- Streaming protocol handling per provider
- Tool ID coordination
- Message accumulation strategies

### 📊 **Typed Output**
Structured JSON output across providers. See [[Typed-Output-Architecture]].
- Native schema support where available
- Tool-based fallback pattern
- Schema validation

### 💬 **Message Handling**
Clean message semantics and transformations. See [[Message-Handling-Architecture]].
- Request/response pair semantics
- Tool result consolidation
- Provider-specific mappers

### 🧠 **Thinking (Extended Reasoning)**
LLM reasoning transparency across providers. See [[Thinking]].
- Streaming thinking deltas via `ChatResult.thinking` field
- Provider-specific configuration (OpenAI Responses, Anthropic, Google)
- Agent-level enablement with provider-specific fine-tuning options
- Token budget controls and dynamic thinking support

### 🎨 **Media Generation**
Provider-agnostic media synthesis capabilities. See [[Media-Generation]].
- Unified `MediaGenerationModel` contract for images, PDFs, audio, and more
- Streaming delivery of binary assets and metadata
- MIME type negotiation and output schema support
- Integrates with server-side tooling when available

### 🛠️ **Server-Side Tools**
Provider-hosted capabilities with progress streaming. See [[Server-Side-Tools-Tech-Design]].
- Web search, image generation, code interpreter
- Streaming event metadata
- Content deliverables as DataParts
- Session persistence

### 📋 **Logging**
Hierarchical, configurable logging. See [[Logging-Architecture]].
- Simple configuration via `Agent.loggingOptions`
- Domain-based organization
- Production-ready patterns

### 🧪 **Testing**
Comprehensive testing strategy. See [[Test-Spec]].
- Capability-based provider filtering
- 80% vs edge case separation
- No regression or performance tests

## Key Implementation Patterns

### Agent Usage
```dart
// Simple usage with defaults
final agent = Agent('openai');
await agent.send('Hello!');

// Specific models
final agent = Agent('openai?chat=gpt-4&embeddings=ada');

// With tools
final agent = Agent('anthropic', tools: [weatherTool]);
await agent.sendStream('What is the weather?');

// Embeddings
final embedding = await agent.embedQuery('search text');
```

### Orchestrator Selection
```dart
// Automatic selection based on request
if (outputSchema != null) {
  return TypedOutputStreamingOrchestrator();
}
return DefaultStreamingOrchestrator();
```

### Provider Discovery
```dart
// Get all providers
final allProviders = Agent.allProviders;

// Discover models and their capabilities
for (final provider in allProviders) {
  await for (final model in provider.listModels()) {
    print('${model.name}: ${model.kinds}');
  }
}
```

## Development Guidelines

### Adding New Providers
1. Extend Provider base class
2. Declare capabilities accurately
3. Implement createChatModel() and createEmbeddingsModel()
4. Add to Provider registry
5. Update tests with new provider

### Adding New Features
1. Identify appropriate layer
2. Follow separation of concerns
3. Update relevant specifications
4. Add capability if provider-specific
5. Include tests following 80/20 rule

### Debugging Issues
1. Enable logging: `Agent.loggingOptions = LoggingOptions(level: Level.FINE)`
2. Check provider capabilities
3. Use curl for API ground truth
4. Reference specification documents
5. Let exceptions bubble up

## Complete Documentation Index

### Core Architecture
- **[[Home]]** - This document: comprehensive overview of the dartantic_ai package architecture
- **[[Unified-Provider-Architecture]]** - Single provider interface for both chat and embeddings operations with capability discovery
- **[[Orchestration-Layer-Architecture]]** - Coordinates streaming workflows, tool execution, and business logic across providers
- **[[Message-Handling-Architecture]]** - Message structure and transformation semantics across Agent and Mapper layers
- **[[State-Management-Architecture]]** - StreamingState system for managing mutable state during streaming operations
- **[[Architecture-Best-Practices]]** - Core architectural principles (DRY, SRP, KISS, YAGNI, separation of concerns, error transparency)

### Features & Capabilities
- **[[Streaming-Tool-Call-Architecture]]** - Provider-specific streaming patterns, tool ID coordination, and message accumulation
- **[[Typed-Output-Architecture]]** - Structured JSON output with native schema support and tool-based fallback
- **[[Thinking]]** - Extended reasoning support across OpenAI Responses, Anthropic, and Google with streaming deltas and token budget controls
- **[[Media-Generation]]** - Provider-agnostic media synthesis capabilities (images, PDFs, audio) with streaming delivery and MIME type negotiation
- **[[Logging-Architecture]]** - Hierarchical, configurable logging with domain-based organization
- **[[Server-Side-Tools-Tech-Design]]** - Architecture for provider-executed tools (web search, code interpreter, image generation)

### Configuration & Setup
- **[[Agent-Config-Spec]]** - API key resolution, environment variables, and cross-platform configuration
- **[[Model-Configuration-Spec]]** - Provider defaults and model resolution patterns
- **[[Model-String-Format]]** - Model string parsing formats (URI-based, colon, slash notation)

### Implementation Guides
- **[[Provider-Implementation-Guide]]** - Step-by-step guide for adding new providers
- **[[OpenAI-Compat]]** - OpenAI-compatible provider setup, API keys, and configuration
- **[[Test-Spec]]** - Comprehensive testing strategy with capability-based filtering

## Future Considerations

- **Vision/Audio**: Capability system ready for expansion
- **Batch Processing**: Orchestration layer foundation exists
- **Parallel Tool Execution**: Infrastructure supports ParallelToolExecutor
- **Custom Orchestrators**: Pluggable workflow patterns
- **Performance Monitoring**: Hooks available in orchestrators

This architecture provides a robust, maintainable foundation for diverse LLM providers while maintaining a clean, consistent API. The six-layer design with orchestration-based workflows enables complex features without compromising simplicity.
