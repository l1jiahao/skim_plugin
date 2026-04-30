# Skim LLM Sidebar

An experimental macOS companion sidebar for Skim. It watches the front PDF in Skim, indexes the document locally, and sends selected context to an OpenAI-compatible chat endpoint.

## What Works

- Reads the front Skim document through AppleScript.
- Docks the companion window next to Skim through System Events.
- Extracts text from the current PDF with PDFKit.
- Stores page-aware chunks in a local SQLite FTS5 index.
- Builds prompt context from selected text, current page text, document summary, and retrieved chunks.
- Calls an OpenAI-compatible `/v1/chat/completions` endpoint with streamed responses.
- Optionally attaches the complete PDF using OpenAI-style chat file input when the configured provider supports it.
- Persists per-paper chat sessions locally, with a history panel for opening, counting, creating, and deleting conversations.

## Run

Requires a working Xcode or Command Line Tools install with SwiftPM.

```sh
swift run SkimLLMSidebar
```

For normal macOS privacy prompts, build an app bundle instead:

```sh
scripts/build-app.sh
open .build/SkimLLMSidebar.app
```

The first run may trigger macOS Automation and Accessibility prompts so the app can read Skim state and dock beside its window.

## Settings

- `Base URL`: defaults to `https://api.openai.com/v1`.
- `Model`: editable; defaults to `gpt-4o-mini`.
- `API key`: stored locally at `~/Library/Application Support/SkimLLMSidebar/provider-api-key` with `0600` file permissions. Keychain is not used.
- `Provider supports PDF file input`: enables the full-PDF attachment capability.
- `Attach the complete PDF when supported`: sends the current PDF as a base64 file payload alongside the text context.

Many OpenAI-compatible gateways only implement text chat completions. Keep PDF attachment disabled unless your provider supports OpenAI-style file input in chat messages.

DeepSeek is supported as a first-class preset. It uses extracted full-paper text as a stable long-context prefix rather than PDF file upload, with `Fast Reading` and `Deep Analysis` modes in the sidebar. See [DeepSeek Paper Reading Mode](docs/deepseek-paper-mode.md).

Chat input uses `Enter` to send and `Shift+Enter` for a newline. During streaming, the message view only auto-follows when it is already near the bottom, so scrolling up to read older text is not pulled back down by new tokens.

Paper-reading memory and prompt behavior are documented in [Paper Memory and Prompting](docs/paper-memory-and-prompts.md).

## Data

The local index is stored at:

```text
~/Library/Application Support/SkimLLMSidebar/index.sqlite
```

The provider API key is stored at:

```text
~/Library/Application Support/SkimLLMSidebar/provider-api-key
```

Per-paper chat sessions, message full-text search, page-citation evidence references, and future research-memory records are stored in:

```text
~/Library/Application Support/SkimLLMSidebar/chat.sqlite
```

No Skim notes are modified in this MVP.

## Current Limitations

- This is a companion window, not a native Skim plugin.
- Scanned PDFs without extractable text require OCR; OCR is not included yet.
- Skim selected-text AppleScript support may vary by Skim version; the app falls back to page and retrieval context.
- Full-PDF attachment is capped at 50 MB before sending.
