# Cipher MCP Server -- Deep Dive Research Report

> Research date: 2026-03-15
> Source: https://github.com/campfirein/cipher (Byterover Cipher)
> Purpose: Inform xgh design decisions around memory layer integration

---

## 1. Overview

Cipher is an open-source **memory layer for coding agents**, compatible with Cursor, Claude Code, Codex, Windsurf, Cline, Gemini CLI, Kiro, VS Code, Roo Code, Trae, Amp Code, and Warp via MCP. It provides:

- **Dual Memory Layer**: System 1 (knowledge/business logic/past interactions) + System 2 (reasoning traces)
- **Workspace Memory**: Team collaboration, project progress tracking, shared context
- **Knowledge Graph**: Neo4j-backed entity/relationship management (optional)
- **Cross-tool sharing**: Same memory accessible from different IDEs/agents
- **Multiple vector backends**: Qdrant, Milvus, ChromaDB, Pinecone, Pgvector, Faiss, Redis, in-memory

---

## 2. All Available Tools

### 2.1 Memory Tools (agent-accessible)

| Tool | Agent-Accessible | Purpose |
|------|-----------------|---------|
| `cipher_extract_and_operate_memory` | Yes | Extracts knowledge from interactions; applies ADD/UPDATE/DELETE/NONE atomically |
| `cipher_memory_search` | Yes | Semantic search over stored knowledge memory |
| `cipher_store_reasoning_memory` | **No** (internal) | Stores reasoning traces (append-only reflection memory) |

### 2.2 Reasoning / Reflection Tools

| Tool | Agent-Accessible | Purpose |
|------|-----------------|---------|
| `cipher_extract_reasoning_steps` | **No** (internal) | Extracts structured reasoning steps from user input |
| `cipher_evaluate_reasoning` | **No** (internal) | Evaluates reasoning trace quality, generates improvement suggestions |
| `cipher_search_reasoning_patterns` | Yes | Searches reflection memory for relevant reasoning patterns |

### 2.3 Workspace Memory Tools

| Tool | Agent-Accessible | Purpose |
|------|-----------------|---------|
| `cipher_workspace_search` | Yes | Searches team/project workspace memory for progress, bugs, PRs, collaboration context |
| `cipher_workspace_store` | **No** (internal, background) | Captures team/project signals into workspace memory automatically after interactions |

### 2.4 Knowledge Graph Tools (requires `KNOWLEDGE_GRAPH_ENABLED=true` + Neo4j)

| Tool | Purpose |
|------|---------|
| `cipher_add_node` | Add entity to knowledge graph |
| `cipher_update_node` | Update entity |
| `cipher_delete_node` | Delete entity |
| `cipher_add_edge` | Create relationship between entities |
| `cipher_search_graph` | Basic graph search |
| `cipher_enhanced_search` | Enhanced search strategies |
| `cipher_get_neighbors` | Retrieve related entities around a node |
| `cipher_extract_entities` | Extract entities from text for graph insertion |
| `cipher_query_graph` | Run graph queries, retrieve structured results |
| `cipher_relationship_manager` | Higher-level relationship operations |

### 2.5 System Tools

| Tool | Purpose |
|------|---------|
| `cipher_bash` | Execute bash commands (one-off or persistent sessions with working dir and timeout) |
| `ask_cipher` | Conversational interface (only tool in "default" MCP mode) |

---

## 3. Workspace Memory System -- Deep Dive

### 3.1 What It Is

Workspace memory is a **separate vector collection** dedicated to team collaboration context. While default memory focuses on technical knowledge/code patterns, workspace memory tracks:

- **Who is working on what** (team member activities)
- **Project progress** (feature status, completion percentages)
- **Bug tracking** (descriptions, severity, status)
- **Work context** (project, repository, branch)
- **Domain tagging** (frontend, backend, devops, quality-assurance, design)

### 3.2 Architecture: Three Separate Collections

Cipher uses a `MultiCollectionVectorManager` that manages **three independent vector collections**:

1. **Knowledge collection** (`VECTOR_STORE_COLLECTION_NAME`): Factual information, code patterns, technical knowledge
2. **Reflection collection** (`REFLECTION_VECTOR_STORE_COLLECTION`): Reasoning traces and evaluations
3. **Workspace collection** (`WORKSPACE_VECTOR_STORE_COLLECTION`): Team progress, bugs, collaboration context

Each collection can theoretically use a different vector store backend, though typically they share the same Qdrant/Milvus instance with different collection names. The workspace collection can be configured with entirely separate host/port/credentials via `WORKSPACE_VECTOR_STORE_*` env vars.

### 3.3 Configuration Modes

Three modes of operation:

| Mode | Config | Effect |
|------|--------|--------|
| **Hybrid** (default) | `USE_WORKSPACE_MEMORY=true` | Both workspace AND default knowledge memory active |
| **Workspace-only** | `USE_WORKSPACE_MEMORY=true` + `DISABLE_DEFAULT_MEMORY=true` | Only workspace tools exposed; no knowledge/reasoning memory |
| **Technical-only** | `USE_WORKSPACE_MEMORY=false` (default) | Only knowledge + reflection memory; no workspace tools |

### 3.4 Cross-Tool Memory Sharing (Team Scoping)

Three env vars control memory scoping/sharing:

| Env Var | Purpose | Example |
|---------|---------|---------|
| `CIPHER_USER_ID` | Team/user identifier | `rokamenu-team`, `frontend-team` |
| `CIPHER_PROJECT_NAME` | Project identifier | `rokamenu`, `ecommerce-app` |
| `CIPHER_WORKSPACE_MODE` | `shared` or `isolated` | `shared` |

When `CIPHER_WORKSPACE_MODE=shared`, all Cipher instances with the same `CIPHER_USER_ID` and `CIPHER_PROJECT_NAME` read/write the same workspace memory. This is how team sharing works -- different developers each run their own Cipher MCP server, but all point to the same Qdrant collection with the same user/project IDs.

In `isolated` mode (default), each instance's memories are scoped and not shared.

**Implementation detail**: These IDs are stored as payload fields (`userId`, `projectId`, `workspaceMode`) on every vector entry. In shared mode, search filters on these fields to return only matching team memories. Env vars take precedence over programmatic values for security.

### 3.5 Workspace Store Tool -- How It Works

`cipher_workspace_store` is an **internal, background tool** (not agent-accessible). It:

1. **Receives interaction text** (string or array of strings)
2. **Filters for significance** via `isWorkspaceSignificantContent()` -- regex-based pattern matching that skips greetings, tool results, yes/no responses, and personal info queries
3. **Matches workspace patterns** -- looks for team/collaboration keywords, project/progress keywords, bug tracking terms, code review/deployment terms
4. **Extracts structured info** via `extractWorkspaceInfo()` -- pulls out team member names, progress status, bug reports, work context (project/repo/branch), domain
5. **Checks for duplicates** via vector similarity search against existing workspace memories
6. **Stores as workspace payload** with all structured fields embedded in the vector entry's payload

The tool accepts an `interaction` parameter that can be either a single string or an array of strings.

### 3.6 Workspace Search Tool -- Parameters

```typescript
{
  query: string,              // Natural language search query (required)
  top_k: number,              // Max results (default: 10, max: 50)
  similarity_threshold: number, // Min similarity (default: from WORKSPACE_SEARCH_THRESHOLD env, typically 0.4)
  filters: {
    domain: 'frontend' | 'backend' | 'devops' | 'quality-assurance' | 'design',
    teamMember: string,       // Filter by team member name
    project: string           // Filter by project name
  },
  include_metadata: boolean,  // Include detailed metadata (default: true)
  enable_query_refinement: boolean // LLM-powered query rewriting (default: false)
}
```

Search returns results with workspace-specific fields: `teamMember`, `currentProgress` (feature, status, completion%), `bugsEncountered` (description, severity, status), `workContext` (project, repo, branch), `domain`, `confidence`, `qualitySource`.

### 3.7 Workspace Payload Structure

```typescript
interface WorkspacePayload extends BasePayload {
  tags: string[];
  confidence: number;
  event: 'ADD' | 'UPDATE' | 'DELETE' | 'NONE';
  teamMember?: string;
  currentProgress?: {
    feature: string;
    status: 'in-progress' | 'completed' | 'blocked' | 'reviewing';
    completion?: number;  // 0-100
  };
  bugsEncountered?: Array<{
    description: string;
    severity: 'low' | 'medium' | 'high' | 'critical';
    status: 'open' | 'in-progress' | 'fixed';
  }>;
  workContext?: {
    project?: string;
    repository?: string;
    branch?: string;
  };
  domain?: string;  // 'frontend', 'backend', 'devops', etc.
  sourceSessionId?: string;
  qualitySource: 'similarity' | 'llm' | 'heuristic';
  // Cross-tool sharing (from BasePayload)
  userId?: string;
  projectId?: string;
  workspaceMode?: 'shared' | 'isolated';
}
```

---

## 4. Memory Types Summary

| Memory Type | Collection | Payload Type | Operation Mode |
|-------------|-----------|--------------|----------------|
| **Knowledge** | `VECTOR_STORE_COLLECTION_NAME` | `KnowledgePayload` | ADD/UPDATE/DELETE/NONE |
| **Reflection/Reasoning** | `REFLECTION_VECTOR_STORE_COLLECTION` | `ReasoningPayload` | Append-only |
| **Workspace** | `WORKSPACE_VECTOR_STORE_COLLECTION` | `WorkspacePayload` | ADD/UPDATE/DELETE/NONE |

**Knowledge memory** stores: factual information, code patterns, technical knowledge, domain info, code_pattern references, old_memory for updates.

**Reflection memory** stores: reasoning step arrays (type: thought/action/observation/decision/conclusion/reflection + content), quality evaluations (score, issues, suggestions), task context (goal, input, taskType, domain, complexity).

**Workspace memory** stores: team activities, project progress, bug reports, work context (repo/branch/project), domain assignments.

---

## 5. Search Capabilities

### 5.1 Vector Similarity Search
All search tools use **embedding-based semantic search**. Text is embedded, then searched via cosine similarity against the vector store.

### 5.2 Query Refinement (Optional)
Both `cipher_memory_search` and `cipher_workspace_search` support `enable_query_refinement` (or global env `ENABLE_QUERY_REFINEMENT=true`). This uses the LLM to rewrite the user's query into multiple optimized search queries, then searches with all of them (via `embedBatch`). Results are deduplicated and merged.

### 5.3 Filtering
- **Workspace search**: Filters by `domain`, `teamMember`, `project` (post-retrieval filtering on payload fields)
- **Knowledge search**: No explicit filters beyond similarity threshold
- **Reasoning search**: Filters on `CIPHER_WORKSPACE_MODE=shared` for cross-tool sharing

### 5.4 No Keyword/Hybrid Search
Cipher does **not** implement keyword search or hybrid search (vector + keyword). All search is purely vector-based with optional LLM query refinement.

---

## 6. Examples Walkthrough

### Example 01: Kimi K2 Coding Assistant
- Uses OpenRouter with Kimi K2 model for coding tasks
- Integrates filesystem MCP server + Firecrawl for web research
- Demonstrates: custom system prompts, multi-MCP-server config, `evalLlm` for evaluation tasks

### Example 02: CLI Coding Agents
- Claude Code + Gemini CLI memory layer
- Demonstrates: persistent memory across CLI sessions, cross-session learning
- Uses Anthropic Claude as LLM, OpenAI for embeddings
- Key: shows `.mcp.json` config for Claude Code integration

### Example 03: Strict Memory Layer
- Pure memory service for external agents
- Only exposes `ask_cipher` tool (default MCP mode, not aggregator)
- Storage runs in background automatically; retrieval via `ask_cipher`
- System prompt is focused: "You are a MEMORY LAYER"
- Demonstrates: `MCP_SERVER_MODE=default`, `DISABLE_REFLECTION_MEMORY=true`

### Example 04: MCP Aggregator Hub
- Cipher as a hub aggregating multiple MCP servers (Exa Search, Context7, Semgrep, TaskMaster)
- Demonstrates: `MCP_SERVER_MODE=aggregator`, multiple transport types (stdio, streamable-http)
- Shows tool prefixing/namespacing for conflict resolution
- Demonstrates `enabled: false` to disable specific MCP servers

### Example 05: Workspace Memory Team Progress
- Full workspace memory setup for team collaboration
- Config: `MCP_SERVER_MODE=aggregator`, `USE_WORKSPACE_MEMORY=true`, `DISABLE_DEFAULT_MEMORY=true`
- Uses `USE_ASK_CIPHER=false` to disable LLM usage (only embeddings needed)
- Demonstrates: workspace-only mode, Qdrant with explicit dimension/collection config
- Two tools exposed: `cipher_workspace_search` + `cipher_workspace_store`
- Natural language examples: "John is working on auth feature, 60% complete", "Sarah fixed the login bug"

---

## 7. Configuration Reference

### 7.1 Key Environment Variables

**Core:**
- `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`, etc. (at least one required)
- `MCP_SERVER_MODE`: `default` (only `ask_cipher`) or `aggregator` (all tools exposed)

**Vector Store:**
- `VECTOR_STORE_TYPE`: `qdrant`, `milvus`, `chromadb`, `pinecone`, `pgvector`, `faiss`, `redis`, `in-memory`
- `VECTOR_STORE_URL`, `VECTOR_STORE_HOST`, `VECTOR_STORE_PORT`, `VECTOR_STORE_API_KEY`
- `VECTOR_STORE_COLLECTION_NAME`: Knowledge memory collection name
- `VECTOR_STORE_MAX_VECTORS`: Max vectors per collection (default: 10000)

**Reflection Memory:**
- `REFLECTION_VECTOR_STORE_COLLECTION`: Collection name for reasoning traces
- `DISABLE_REFLECTION_MEMORY`: Set to `true` to disable

**Workspace Memory:**
- `USE_WORKSPACE_MEMORY`: `true` to enable
- `DISABLE_DEFAULT_MEMORY`: `true` for workspace-only mode
- `WORKSPACE_VECTOR_STORE_COLLECTION`: Collection name (default: `workspace_memory`)
- `WORKSPACE_SEARCH_THRESHOLD`: Similarity threshold (default: 0.4 via env, 0.7 in config schema)
- `WORKSPACE_VECTOR_STORE_TYPE`: Can differ from main vector store
- `WORKSPACE_VECTOR_STORE_DIMENSION`: Embedding dimension (default: 1536)
- `WORKSPACE_VECTOR_STORE_MAX_VECTORS`: Max vectors (default: 10000)
- `WORKSPACE_VECTOR_STORE_HOST/PORT/URL/API_KEY`: Separate workspace vector store connection

**Cross-Tool Sharing:**
- `CIPHER_USER_ID`: Team identifier for shared memory
- `CIPHER_PROJECT_NAME`: Project identifier for shared memory
- `CIPHER_WORKSPACE_MODE`: `shared` or `isolated`

**Search:**
- `ENABLE_QUERY_REFINEMENT`: LLM-powered query rewriting for better search
- `MEMORY_SEARCH_MODE`: `knowledge`, `reflection`, or `both`

**Knowledge Graph (optional):**
- `KNOWLEDGE_GRAPH_ENABLED`: `true` to enable
- `KNOWLEDGE_GRAPH_URI`: Neo4j bolt URI
- `KNOWLEDGE_GRAPH_USERNAME/PASSWORD/DATABASE`: Neo4j credentials

**MCP Transport:**
- `--mcp-transport-type`: `stdio` (default), `sse`, `streamable-http`
- `--mcp-port`: Port for SSE/HTTP transports

**Other:**
- `USE_ASK_CIPHER`: `false` to disable the `ask_cipher` conversational tool (saves LLM costs in aggregator mode)
- `ENABLE_LAZY_LOADING`: `true` for lazy-loaded memory extraction
- `CIPHER_LOG_LEVEL`: Logging level

### 7.2 cipher.yml Configuration

```yaml
llm:
  provider: openai | anthropic | openrouter | ollama | qwen | lmstudio | aws | azure
  model: model-name
  apiKey: $ENV_VAR
  maxIterations: 50
  temperature: 0.1          # optional
  baseURL: custom-endpoint  # optional

evalLlm:                    # optional: separate model for evaluation tasks
  provider: ...
  model: ...

embedding:                  # optional: auto-detected from LLM provider if omitted
  type: openai | gemini | ollama | lmstudio | voyage | qwen | aws-bedrock
  model: model-name
  apiKey: $ENV_VAR
  dimensions: 1536          # required for fixed-dimension providers

systemPrompt: |
  Your custom system prompt here

mcpServers:
  server-name:
    type: stdio | streamable-http
    command: ...             # for stdio
    url: ...                 # for streamable-http
    args: [...]
    env: {...}
    enabled: true | false
```

### 7.3 Advanced System Prompt Providers

Cipher supports a provider-based system prompt architecture (`memAgent/cipher-advanced-prompt.yml`):

- **static**: Fixed content injected at a priority level
- **dynamic**: LLM-generated (summary, rules, error-detection generators)
- **file-based**: Loaded from a markdown file (e.g., `project-guidelines.md`)

---

## 8. Architecture

### 8.1 Runtime Modes

| Mode | Command | Purpose |
|------|---------|---------|
| `cli` | `cipher` | Interactive terminal chat |
| `mcp` | `cipher --mode mcp` | MCP server (stdio/SSE/HTTP) |
| `api` | `cipher --mode api` | REST API server |
| `ui` | `cipher --mode ui` | Web UI |

### 8.2 MCP Server Modes

| Mode | Env Var | Tools Exposed |
|------|---------|---------------|
| `default` | `MCP_SERVER_MODE=default` | Only `ask_cipher` (conversational interface) |
| `aggregator` | `MCP_SERVER_MODE=aggregator` | All memory tools + workspace tools + KG tools + bash + connected MCP server tools |

### 8.3 Embedding Pipeline

1. Text input received
2. Embedding generated via configured provider (OpenAI, Gemini, Ollama, LM Studio, Voyage, Qwen, AWS Bedrock, Azure OpenAI)
3. Vector stored in configured backend with structured payload
4. Search: query embedded, cosine similarity search, optional query refinement

### 8.4 Storage Architecture

- **Vector stores**: 8 backends supported (Qdrant, Milvus, ChromaDB, Pinecone, Pgvector, Faiss, Redis, in-memory)
- **Chat history**: PostgreSQL (recommended), SQLite, or in-memory
- **Knowledge graph**: Neo4j (optional)
- **Session storage**: Integrated with chat history backend

---

## 9. Features We Might Not Be Using in xgh

Based on the current xgh setup (which uses Cipher in aggregator mode with the standard memory tools), the following Cipher features are potentially underutilized:

### 9.1 Currently Unused / Underexplored

1. **Knowledge Graph** (`KNOWLEDGE_GRAPH_ENABLED`): Full Neo4j-backed entity/relationship graph. 12 tools for managing entities, relationships, and graph queries. Could be powerful for mapping codebase architecture.

2. **Workspace Memory with Team Sharing** (`USE_WORKSPACE_MEMORY` + `CIPHER_WORKSPACE_MODE=shared`): Designed exactly for multi-agent team collaboration. Different team members' Cipher instances share the same workspace memory.

3. **Separate Workspace Vector Store**: Workspace memory can use a completely different vector store backend/host than the main knowledge memory. Useful for isolating team context from individual technical knowledge.

4. **Query Refinement** (`ENABLE_QUERY_REFINEMENT`): LLM-powered query rewriting that generates multiple optimized search queries from a single input. Could significantly improve search recall.

5. **Advanced System Prompt Providers**: Dynamic, file-based, and static prompt providers with priority ordering. Could replace or augment the current xgh prompt injection approach.

6. **evalLlm Configuration**: Separate, cheaper model for evaluation tasks (memory extraction quality, reasoning evaluation). Reduces costs on the primary model.

7. **Web Search Tools**: Built-in web search tool support (requires separate API keys).

8. **Chat History Persistence**: PostgreSQL/SQLite-backed conversation history with session management. We may only be using in-memory.

9. **Event System**: Event filtering (`EVENT_FILTERING_ENABLED`), persistence (`EVENT_PERSISTENCE_ENABLED`), and typed event management for tool execution monitoring.

10. **Lazy Loading** (`ENABLE_LAZY_LOADING`): Lazy-loaded memory extraction to reduce startup time.

### 9.2 Workspace Memory -- Key Design Insight for xgh

The workspace memory system is the most relevant unexplored feature. Key insights:

- **It is a separate collection**: Does not pollute technical knowledge memory
- **It auto-extracts team context**: The store tool runs in the background and picks up team mentions, progress updates, bug reports via regex patterns
- **Cross-tool sharing is built in**: `CIPHER_USER_ID` + `CIPHER_PROJECT_NAME` + `CIPHER_WORKSPACE_MODE=shared` allows all team members' agents to read/write the same workspace collection
- **It can run workspace-only**: With `DISABLE_DEFAULT_MEMORY=true`, Cipher becomes purely a team collaboration memory layer
- **Structured payloads**: Unlike generic memory, workspace payloads have typed fields for team member, progress status, bugs, work context, domain

The main limitation: workspace_store is **internal-only** (not agent-accessible). The LLM/agent cannot directly call it -- it runs automatically in the background after interactions. This means the agent cannot proactively store workspace information on demand; it must come through natural conversation flow.

---

## 10. Source Code Key Files

| File | Purpose |
|------|---------|
| `src/core/brain/tools/definitions/memory/workspace_search.ts` | Workspace search tool implementation |
| `src/core/brain/tools/definitions/memory/workspace_store.ts` | Workspace store tool implementation |
| `src/core/brain/tools/definitions/memory/workspace-tools.ts` | Workspace tools module (enable/disable logic) |
| `src/core/brain/tools/definitions/memory/workspace-payloads.ts` | Workspace payload structures |
| `src/core/brain/tools/definitions/memory/search_memory.ts` | Knowledge memory search tool |
| `src/core/brain/tools/definitions/memory/extract_and_operate_memory.ts` | Knowledge extraction tool |
| `src/core/brain/tools/definitions/memory/store_reasoning_memory.ts` | Reasoning memory storage |
| `src/core/brain/tools/definitions/memory/payloads.ts` | Base payload types (Knowledge, Reasoning) |
| `src/core/brain/tools/def_reflective_memory_tools.ts` | Reflection tools (extract, evaluate, search reasoning) |
| `src/core/vector_storage/multi-collection-manager.ts` | Manages knowledge + reflection + workspace collections |
| `src/core/vector_storage/dual-collection-manager.ts` | Legacy: manages knowledge + reflection only |
| `src/core/config/workspace-memory-config.schema.ts` | Workspace config schema with Zod validation |
| `docs/workspace-memory.md` | Official workspace memory documentation |
| `docs/builtin-tools.md` | Tool inventory documentation |
