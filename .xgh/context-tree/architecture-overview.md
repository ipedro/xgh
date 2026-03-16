---
title: xgh Architecture Overview
type: architecture
status: validated
importance: 95
tags: [architecture, overview, core]
keywords: [xgh, tech-pack, MCS, memory, context-tree, cipher, dual-engine]
created: 2026-03-16
updated: 2026-03-16
---

# xgh Architecture Overview

xgh (eXtreme Go Horse) is a **Model Context Server (MCS) tech pack** for Claude Code that gives AI agents persistent, team-shared memory across sessions.

## Three-Layer Stack

1. **Memory Layer (Dual-Engine)**
   - **Cipher MCP**: Semantic vector search via Qdrant + embeddings (workspace memory, reasoning traces)
   - **Context Tree**: Git-committed markdown knowledge base (`.xgh/context-tree/*.md`)
   - **Sync Layer**: Keeps both engines consistent

2. **Hook Layer (Self-Learning)**
   - **SessionStart** (`hooks/session-start.sh`): Loads context tree, injects top knowledge into session
   - **UserPromptSubmit** (`hooks/prompt-submit.sh`): Detects intent, injects cipher memory as additionalContext

3. **Skill/Command Layer**
   - 25 skills (auto-triggered or explicit invocation)
   - 18 slash commands (`/xgh-*`)
   - Agents for multi-agent collaboration

## Dual-Engine Search

| Engine | Strength | Storage |
|--------|----------|---------|
| BM25 (Context Tree) | Keyword precision, auditable | Git-committed markdown |
| Cipher (Vector) | Semantic recall | Qdrant collections |

Merged scoring: `0.5 × cipher + 0.3 × bm25 + 0.1 × importance + 0.1 × recency`

## BYOP (Bring Your Own Provider)

Provider-agnostic: supports vllm-mlx (local), OpenAI, Anthropic, OpenRouter for embeddings and LLM.
