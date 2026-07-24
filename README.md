# AI Features

Zestaw skryptów i narzędzi dla CLI / Termux wspierających pracę agentów AI.

## Użycie zmiennej AI_FEATURES

Zmienna `AI_FEATURES` służy do wczytywania dokumentacji/instrukcji dla agentów AI (np. `gemini-chat`) bezpośrednio do prepromptu (system instruction). Możesz wskazać w niej pliki Markdown z instrukcjami dla agentów (rozdzielone dwukropkami, jeśli jest ich wiele).

### Jak dodać zestaw narzędzi (np. playwright-tooling)

Dodaj w swoim pliku `~/.bashrc` lub `~/logins.sh` eksport zmiennej `AI_FEATURES`:

```bash
export AI_FEATURES="$HOME/playwright-tooling/Agents.md"
```

Jeśli chcesz przekazać wiele plików z dokumentacją, rozdziel je dwukropkiem:

```bash
export AI_FEATURES="$HOME/playwright-tooling/Agents.md:$HOME/inne-narzedzie/Agents.md"
```
