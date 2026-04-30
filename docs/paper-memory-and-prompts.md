# Paper Memory and Prompting

This document describes how Skim LLM Sidebar records paper-reading conversations and how prompts are shaped so those records stay useful for later retrieval.

## Goals

The chat history is not only a transcript. It is designed to become a paper-reading memory layer that can later support RAG queries such as:

- all questions asked about one paper
- how the user developed an understanding of a method
- all assistant claims backed by page citations
- unresolved questions and follow-up tasks
- discussions about ablations, baselines, limitations, and failure cases
- similar claims or methods across papers

## System Prompt Contract

The system prompt is defined in `PromptBuilder` and is shared by the normal PDF context path and the DeepSeek long-context path.

The key behavior contract is:

- Use only supplied PDF content for paper-specific claims.
- Do not fill gaps with outside knowledge unless the user explicitly asks for background, and label that background separately.
- Cite every key paper claim with page markers such as `[p. N]`.
- Include section, figure, table, equation, algorithm, or citation identifiers when they are visible in the supplied context.
- If the context is insufficient, say what is missing instead of guessing.
- State OCR, scanned-PDF, or extraction limitations directly.
- Prioritize methods, assumptions, experiment design, baselines, metrics, ablations, statistical results, limitations, and failure cases over fluent abstract-style summaries.
- Separate paper evidence from model inference.
- Answer in the user's language unless asked otherwise.

The system prompt matters for persistence because downstream memory depends on answers being evidence-bound. If assistant messages contain page markers and explicit uncertainty, the storage layer can later index claims, evidence, and open questions with less ambiguity.

## Prompt Assembly

For a normal OpenAI-compatible provider, each request contains:

```text
system:
  Paper reading behavior and citation rules.

recent chat history:
  Short compatibility window.

user:
  Document title.
  Extractive document summary when available.
  User-selected text.
  Current page text.
  Retrieved PDF chunks with [p. N] markers.
  Optional full-PDF attachment notice.
  Current question.
```

For DeepSeek long-context mode, each request contains:

```text
system:
  Paper reading behavior and citation rules.

user:
  Stable document prefix:
  title + full extracted paper text with [p. N] page markers.

assistant:
  Document loaded.

previous chat turns:
  Complete local chat history.

user:
  Current question + selected text + current page text.
```

DeepSeek chat completions are stateless, so resuming a conversation works by loading the saved messages locally and sending them again with the current request.

## Resume Behavior

When a user opens a saved session from the history panel:

1. The current session is saved if it has user messages.
2. The selected session is loaded from `chat.sqlite`.
3. Messages are restored in their original ordinal order.
4. `activeSessionID` is set to the restored session.
5. The next user question is appended to that restored message list.
6. The LLM request is built from the restored history plus fresh PDF context from the currently open paper.

This makes the UI state and API context align: the visible resumed conversation is also the conversation sent back to the model.

## Storage

Conversation memory is stored separately from the PDF index:

```text
~/Library/Application Support/SkimLLMSidebar/chat.sqlite
```

The PDF text index remains in:

```text
~/Library/Application Support/SkimLLMSidebar/index.sqlite
```

The separation is intentional. The PDF index can be rebuilt, but paper-reading history should survive reindexing.

## SQLite Schema

`chat.sqlite` currently contains these logical groups:

```text
papers
  One row per known paper identity.

sessions
  One row per conversation for a paper.

messages
  Ordered raw transcript messages for each session.

message_fts
  Full-text search over message content and reasoning text.

turn_contexts
  Reserved for per-turn selected text, page, retrieved chunks, prompt hash,
  system prompt version, and full-document prefix hash.

evidence_refs
  Structured references extracted from assistant answers, currently page
  citations like [p. N].

research_memory
  Reserved for derived reading memory such as claim, limitation, method,
  open question, todo, insight, contradiction, or replication note.

research_memory_fts
  Full-text search over derived memory records.
```

The current implementation writes `papers`, `sessions`, `messages`, `message_fts`, and `evidence_refs`. `turn_contexts` and `research_memory` are present so future RAG features can be added without replacing the database.

## Evidence References

When a session is saved, assistant messages are scanned for page citations:

```text
[p. 7]
[page 12]
```

Each match is stored in `evidence_refs` with:

- paper ID
- session ID
- message ID
- page number
- a short quote from the containing line
- timestamp

This lets future features answer questions like "show all page-cited conclusions for this paper" without parsing every transcript again.

## Future RAG Path

The next step is to populate `research_memory` from the transcript. A practical memory extractor should create compact records such as:

```text
type: method
content: The paper transfers policy priors from human videos to robot execution.
source_message_id: ...
evidence_ref_id: ...

type: limitation
content: The experiments only report task progress on a narrow task set.
source_message_id: ...
evidence_ref_id: ...

type: open_question
content: Check whether the ablation isolates video transfer from model capacity.
source_message_id: ...
status: open
```

These records can be embedded later and joined back to raw messages, pages, and evidence references. Raw transcript search remains useful, but derived memory gives a higher-signal retrieval layer for literature review and cross-paper comparison.

## Current Limitations

- Paper identity currently uses a hash of the standardized file path. The schema already has room for `file_hash`, `doi`, and `arxiv_id`, but those are not populated yet.
- Message embeddings are not stored yet.
- `turn_contexts` is reserved but not written yet.
- `research_memory` is reserved but not automatically extracted yet.
- DeepSeek mode sends complete local history, but the provider context limit still applies.
