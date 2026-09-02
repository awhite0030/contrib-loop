Reviewer (will-lamerton) CHANGES_REQUESTED. Blocking items:

1. OAuth providers (github-copilot, chatgpt-codex) report "API Key: Not set" when fully authenticated. loadProviderConfigs() substitutes literal 'dummy-key' when no apiKey, but those providers authenticate through stored device-flow credentials (validateProviderCredentials, source/client-factory.ts:239). Branch on currentProvider.sdkProvider and use loadCopilotCredential / loadCodexCredential. Local providers like Ollama should read "Not required (local)" not "Not set".

2. Key masking threshold <= 8 leaks nearly the whole key at lengths 9 to 11. #937 specifically asked for strict middle-hiding so screenshots stay safe. Raise the threshold to ~12 and use a fixed-width mask so output does not disclose key length either.

3. Replace hardcoded borderColor="blue" / color="red" with theme colors (colors.primary / colors.error from useTheme()).

4. Follow the command view convention from source/commands/lsp.tsx: useTheme() and useTerminalWidth() inside TitledBoxWithPreferences with title="/whoami", handler returns React.createElement(...) with generateKey('whoami'). Right now the result has no React key so the chat queue falls back to an unstable index key (source/components/chat-queue.tsx:15).

5. Add a render test following doctor.spec.tsx with renderWithTheme + strip-ansi: assert that a config with apiKey 'sk-verysecretvalue1234' renders without 'verysecretvalue', and cover the unknown-provider branch and the new boundary lengths.

6. Add /whoami and /auth to docs/features/commands.md.

7. Lowercase both sides of exact-match provider lookup (resolveProviderName resolves case-insensitive at source/client-factory.ts:81).

8. Differentiate /auth from /whoami description; mention relation to /status and /doctor. The genuinely new information here is the masked key.
