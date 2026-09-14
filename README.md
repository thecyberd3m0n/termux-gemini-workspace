# AI Features

A set of CLI scripts and utilities for Termux / Bash environments that enhance working with AI models (specifically Gemini) and AI agent workflows.

## Features

- **Gemini Shell Integrations (`gemini.sh`)**:
  - `gemini "question"`: A quick CLI query tool returning direct output from Google Gemini.
  - `gemini-chat`: An interactive autonomous CLI chat session loop capable of running system bash commands, managing context history window compression, injecting system instructions and agent tool documentation automatically.
  - Automatic context compression and token limit management when handling large command outputs or long conversation histories.
- **Environment Auto-installer (`install.sh`)**:
  - Automatically installs necessary binary dependencies (`curl`, `jq`, `python`, `markdownify`).
  - Sources all feature scripts in `~/.bashrc` cleanly and idempotently.
- **AI Agent Documentation Injection (`AI_FEATURES`)**:
  - Dynamically injects external agent instruction sets into `gemini-chat` system prompt via the `AI_FEATURES` environment variable.

## Quick Start / Installation

Run the installation script to configure dependencies and update your `~/.bashrc`:

```bash
./install.sh
source ~/.bashrc
```

Make sure you have `GEMINI_API_KEY` set in your environment (e.g., inside `~/logins.sh`).

## Usage

### Simple Gemini Query

```bash
gemini "How do I extract a tar.gz file in Linux?"
```

### Interactive Gemini Agent Chat

Launch an interactive agent session in your current working directory:

```bash
gemini-chat
```

### Customizing AI Agent Instructions (`AI_FEATURES`)

The `AI_FEATURES` environment variable allows you to load additional Markdown instructions or documentation (e.g. tool specifications like `playwright-tooling` or `puppeteer-tooling`) directly into `gemini-chat` system prompt instructions.

In your `~/.bashrc` or `~/logins.sh`:

```bash
export AI_FEATURES="$HOME/playwright-tooling/Agents.md"
```

To load documentation from multiple tools or sources, separate paths with a colon (`:`):

```bash
export AI_FEATURES="$HOME/playwright-tooling/Agents.md:$HOME/puppeteer-tooling/Agents.md"
```
