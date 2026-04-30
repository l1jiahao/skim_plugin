# DeepSeek Paper Reading Mode

This document describes the DeepSeek-optimized path used by Skim LLM Sidebar for paper reading.

## Why DeepSeek Is Different

DeepSeek's API is OpenAI-compatible at the chat-completions layer, but its documented strengths for this use case are long context and context caching:

- DeepSeek exposes chat completions at `https://api.deepseek.com/chat/completions`, so the app can keep the existing provider client shape.
- DeepSeek's current generation supports very long context, which makes full extracted paper text practical for many PDFs.
- Context caching is automatic and works best when repeated requests share the same stable prefix.
- Thinking mode can be enabled for difficult reasoning tasks and disabled for fast reading, translation, summarization, and explanation.
- The official API docs do not describe direct PDF/file upload for chat completion requests, so this app sends extracted PDF text rather than the binary PDF.

Official docs:

- Quick start: https://api-docs.deepseek.com/
- Chat completions: https://api-docs.deepseek.com/api/create-chat-completion
- Context caching: https://api-docs.deepseek.com/guides/kv_cache
- Thinking mode: https://api-docs.deepseek.com/guides/thinking_mode
- Pricing and model list: https://api-docs.deepseek.com/quick_start/pricing

## Implementation

The app now has a DeepSeek preset:

- `baseURL`: `https://api.deepseek.com`
- `model`: `deepseek-v4-flash`
- `supportsPDFInput`: `false`
- `contextMode`: `deepSeekLongContext`
- `deepSeekThinkingEnabled`: `false`
- `deepSeekReasoningEffort`: `high`
- `maxLongContextCharacters`: `700000`

The main sidebar exposes two DeepSeek UI modes:

- `Fast Reading`: uses `deepseek-v4-flash` with thinking disabled. This is the default for translation, explanation, section summaries, and fast Q&A.
- `Deep Analysis`: uses `deepseek-v4-pro` with thinking enabled and `reasoning_effort = high`. This is intended for derivations, proof checking, experiment critique, and multi-section reasoning.

The header shows a small `DS` provider badge when the active preset is DeepSeek. The badge is implemented as a reusable provider indicator rather than being hard-wired into the chat logic, so future multimodal providers can add their own preset and badge without changing the paper-reading pipeline.

When the user opens a PDF in Skim, the indexer stores both:

- page-level full text in the `pages` table
- chunked FTS text in the existing `chunks` and `chunks_fts` tables

For DeepSeek long-context mode, each request is built as:

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

The stable document prefix is intentionally placed before the changing question. That shape is meant to improve DeepSeek context-cache reuse across repeated questions about the same paper.

DeepSeek chat completions are stateless, so the app re-sends the local chat history on each request. Switching between `Fast Reading` and `Deep Analysis` changes the selected DeepSeek model and thinking setting, but it does not clear the local conversation.

The durable conversation record lives in `chat.sqlite`, not in the DeepSeek API. See [Paper Memory and Prompting](paper-memory-and-prompts.md) for the session resume flow, message search schema, page-citation evidence references, and the prompt contract that keeps saved memories evidence-bound.

## Fallbacks

The app still keeps retrieval mode:

- If the PDF is scanned and has no extractable text, the app reports that OCR is needed.
- If the full extracted text is too large, it is truncated by `maxLongContextCharacters`.
- If full text is unavailable, the prompt falls back to the extractive summary and retrieved chunks.
- Non-DeepSeek providers continue using the existing RAG-style context package.

## Thinking Mode Defaults

`Fast Reading` disables thinking by default because common paper-reading tasks usually benefit more from speed:

- translate a paragraph
- explain a sentence
- summarize a section
- identify the paper's contribution
- compare method and baseline

Use `Deep Analysis` or enable thinking mode for:

- mathematical derivations
- proof checking
- experimental-design critique
- subtle contradiction analysis
- multi-step reasoning across sections

The UI exposes `reasoning_effort` for DeepSeek thinking mode.

When thinking mode is enabled, streamed `reasoning_content` is rendered separately from the final answer in a collapsible `Thinking` section. The final answer remains the main message body.

## Tradeoffs

Long-context mode is more complete than pure retrieval, but it sends more text per request. Context caching should reduce repeated cost and latency after the first request when the document prefix remains stable.

Keeping complete chat history improves continuity across Fast/Deep mode switches, but very long conversations can still run into the provider's context limit. The full-paper prefix is capped by `maxLongContextCharacters` before it is sent.

RAG is still useful when:

- the document is extremely large
- the provider does not support long context well
- the user only wants quick local explanations
- bandwidth or request size matters more than global context

DeepSeek mode does not upload the original PDF file. It sends only PDFKit-extracted text plus page markers, selected text, current page text, and the user question.
