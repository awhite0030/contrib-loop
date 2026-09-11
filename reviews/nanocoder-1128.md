Thanks for picking this up. The setting itself is right (`default: false` matches what #1096 asked for, and `workspace.getConfiguration` is the correct source here rather than `SettingsManager`, which models `agents.config.json`). One blocker though.

### Blocker: this reverts #1098

The branch predates 8a46cd3a ("restore usage footers when reopening chats"), which added a second call site for `appendUsageIndicator` in the history-replay path. Only the live-turn call site is updated, so after merging main:

```
plugins/vscode/media/chat-panel.js
2065:  function appendUsageIndicator(usage, cost, showTokenUsage) {
2429:      appendUsageIndicator(replayedUsage, replayedUsage.cost);        // 2 args, never gated
2446:      appendUsageIndicator(update.usage, update.cost, update.showTokenUsage);
```

Line 2429 passes no third argument, so `showTokenUsage` is `undefined`, the new guard bails, and reopened chats lose their token/cost line permanently even with the setting on. Merging `origin/main` into this branch (clean merge) and running the existing spec confirms it:

```
✘ [fail]: replayed response usage metadata restores the token and cost line
  source/vscode/chat-panel-turn-footer.spec.ts:102
  Value is not truthy: undefined
```

CI is green only because the branch has not been rebased.

### Suggested fix: gate once, off `syncState`

Attaching the flag to the per-turn ACP update payload is why the replay path was missed, and it has two more costs: it only arrives on `prompt_response`/`done`, so toggling the setting does nothing until the next completed turn (no `onDidChangeConfiguration` listener, though the pattern exists at `extension.ts:130` and `acp-client.ts:47`), and it mixes a UI preference into the ACP message shape.

Pushing it once over `syncState` (`chat-webview-provider.ts:112`, handled at `chat-panel.js:2162`) into a module-level variable read inside `appendUsageIndicator` fixes the replay bug and the live-toggle gap together, and leaves the signature unchanged.

### Also

- No tests. `source/vscode/chat-panel-harness` and `chat-panel-turn-footer.spec.ts` already drive this renderer and assert on the usage line, so on/off across both the live and replay paths is a few lines.
- The changeset targets `nanocoder-vscode`, which is in the `ignore` list in `.changeset/config.json`, so `changeset status` bumps nothing and this ships with no changelog entry. `validate-changesets.js` passes because the name is a real workspace package. #1098, also VS Code only, used `"@nanocollective/nanocoder": patch`.

