### nc-review: needs work — 1 blocking, 6 important, 1 nit

The PR correctly updates `TARGET_REGEX` and widens `SkillMemberKind` to include `'skill'`, but it does not wire that kind through the dispatcher, so a `skill:<name>` subscription still silently does nothing at runtime — `SkillDispatcher.dispatch()` only has branches for `agent`, `command`, and `tool`. The fix as merged would resolve the issue's symptom (regex rejects valid input) but not its underlying cause (skill targets need to actually fire). Several other concerns: weak test coverage, stray `.orig`/`fix.patch` files in the diff, missing changeset, and PR #1064 takes the opposite approach to the same issue.

> **Possible duplicate of #1064** — worth checking before going further.

**🔴 blocking · `completeness` · `source/skills/dispatcher.ts:88`**

Merging this PR resolves only half of #1011. The regex change stops parsing from failing, but the resulting `target: {kind: 'skill', name}` falls straight through `SkillDispatcher.dispatch()` because that method has explicit branches only for `agent`, `command`, and `tool`:

```ts
async dispatch(subscription: Subscription, event: Event): Promise<void> {
    const target = subscription.target;
    if (target.kind === 'agent') { ... return; }
    if (target.kind === 'command') { onUnsupportedTarget(...); return; }
    if (target.kind === 'tool')    { onUnsupportedTarget(...); return; }
    // <-- no branch for 'skill': event silently dropped
}
```

So a user who follows the issue's steps still ends up with a subscription that registers but never fires. At minimum the dispatcher needs an `onUnsupportedTarget` branch for `kind: 'skill'` (matching the existing `command`/`tool` shape) so the failure is loud rather than silent, and ideally the author resolves what "skill:" should actually invoke. The issue says these targets "are supported and documented", but the dispatcher in this PR does nothing for them.

**🟠 important · `tests` · `source/skills/registrar.spec.ts`**

The two new tests cover only the manifest parser and the bundle loader's "does not resolve to a member" check. There is no test for the end-to-end behaviour the issue cares about — namely that a bundle with `subscribe: [{target: skill:some-other-skill}]` actually produces a `Subscription` that survives registration and reaches the dispatcher. Given that the dispatcher currently has no `skill` branch (see completeness finding above), this is the regression the test suite most needs to catch and currently can't.

**🟠 important · `tests` · `source/skills/bundle-loader.spec.ts:107`**

The new bundle-loader test only asserts `errors.length === 0`, `skills.length === 1`, and the parsed `target` string. It does not assert that the subscription survives `mergeSubscriptions` and ends up on the returned `Skill.subscribe[]` (compare the existing `'frontmatter subscription target is resolved to the owning member'` test, which asserts the resolved target string on `skills[0].subscribe`). A regression where the new prefix slipped through the regex but was silently dropped by `mergeSubscriptions` would still pass this test.

**🟠 important · `correctness` · `source/skills/dispatcher.spec.ts:13`**

`fileChangedSub` narrows `target.kind` to `'agent' | 'command' | 'tool'`. After widening `SkillMemberKind` to include `'skill'`, the dispatcher test file no longer matches the union it pretends to constrain — `dispatcher.ts` accepts any `SkillMemberKind` via `subscription.target.kind`. The test signature should be widened in lockstep with the union, or the change introduces a type-vs-runtime drift that the existing spec can no longer pin down.

**🟠 important · `scope` · `fix.patch`**

The PR adds three files that look like dev artifacts and should not be in the tree: `fix.patch` (a copy of the diff), `source/skills/bundle-loader.ts.orig`, and `source/skills/manifest-parser.spec.ts.orig`. They are not referenced from source and serve no purpose at build or test time. CONTRIBUTING expects a focused diff.

**🟠 important · `duplicate`**

PR #1064 (`fix(skills): reject unsupported skill subscription targets`) targets the same issue #1011 with the opposite stance: it would explicitly reject `skill:` targets rather than start accepting them. The maintainer needs to pick one direction (accept and implement, or reject loudly) before either lands; both merging would create two different resolutions to a single bug. This PR's framing — that the issue text prescribes the accept-and-implement fix — is plausible from the implementation notes, but the dispatcher does not actually implement the behaviour the issue describes.

**🟠 important · `changeset`**

The author unchecked the changeset box in the PR template. This is a user-facing behavioural change (a previously-rejected YAML target now parses, and the type union widens) and per CONTRIBUTING needs a `.changeset/*.md` entry.

**⚪ nit · `warranted`**

The fix's framing in the PR description leans on the issue's "Implementation Notes" paragraph as if it were a spec, but the issue itself only describes a reproduction and an expected behaviour ("successfully parsed and registered"). The implementation notes prescribes a one-line regex change that ignores the dispatcher question. A maintainer reviewing the issue cold would not necessarily conclude that accepting the prefix without wiring dispatch is the right answer — the more conservative read of #1011 is "skill: targets are not actually supported, stop pretending they are", which is what #1064 does.

---

<sub>🔴 blocking · 🟠 a reviewer would ask for a change · ⚪ optional</sub>

<sub>Automated code review — correctness, security, design, tests, plus duplicates and scope. A human still decides; this is not a substitute for review and is not exhaustive. The required status checks separately cover lint, formatting, types, unused dependencies, the test suite and the build. This bot never merges. Maintainers can rerun with `/re-review`.</sub>

