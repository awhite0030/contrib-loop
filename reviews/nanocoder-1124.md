Thanks for picking this up, the direction matches the suggested v1 in #1084. Two things need fixing before this lands.

**1. Caret escaping is inert inside double quotes (`template.ts`, `cmdQuote`)**

`cmdQuote` both caret-escapes `%&|<>^` *and* wraps the result in `"`. In cmd.exe `^` is only an escape character outside quotes; inside `"..."` it is a literal character. So every escaped metacharacter leaks a stray `^` into the value.

Using the example from the issue: tool body `type {{ file }}` with `file = "Q3 & Q4.txt"` renders as

```
type "Q3 ^& Q4.txt"
```

and cmd looks for a file literally named `Q3 ^& Q4.txt`. We have traded the old POSIX bug (`type 'notes.txt'`) for a new one on any value containing a metacharacter.

The new specs lock this in rather than catching it: `cmdQuote('%PATH%')` asserting `"^%PATH^%"` is a string that renders as the literal text `^%PATH^%`, not `%PATH%`.

Pick one mechanism, not both. Inside `"` the separators `& | < >` are already inert and need no caret.

**2. `"` is not in the escape set**

The regex is `/[%&|<>^]/g`, so a value containing a double quote terminates the quoted region early and everything after it parses outside quotes. cmd has no backslash escape for `"` under `cmd /c`, which is why the usual handling is to reject or strip `"` (and `%`) from substituted values rather than claim to escape them. At minimum this needs a spec for a value with an embedded `"`.

**3. Needs a real Windows run**

CI is ubuntu-only on every workflow and the PR checklist is unchecked, so nothing here has executed under cmd.exe. The added tests only assert the shape of the rendered string, which is exactly the part that is wrong. Could you paste one manual `cmd.exe` run showing `&` and `%PATH%` arriving literally?

**Minor**

- Circular import: `template.ts` now imports from `handler.ts`, which imports `renderBody` back from `template.ts`. It survives on function hoisting, but `isWindowsCmd` would be better in a small shared module.
- Stale module doc at `source/custom-tools/template.ts:12-20` still says "All scalar values are passed through `shellQuote()`" and "Under cmd.exe the same quotes are not quoting, so this is not an injection barrier". The second line is the thing this PR claims to fix.
- Branch is 62 commits behind `main`, worth a rebase.

