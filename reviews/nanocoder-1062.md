Thanks for tracking this down. The root cause is right and the new test is genuine regression coverage (it fails on `main` as written). I checked the branch out and ran the spec: the new test passes. Two things I'd like changed before merging.

**1. Drop the `totalLines > FILE_READ_PREVIEW_THRESHOLD_LINES` disjunct.**

There is no auto-fallback to metadata for large files. `File Information for` is emitted at `read-file.tsx:48` only, inside `if (args.metadata_only)`. A large file read without the flag returns a 250-line preview plus a `[Truncated at line ...]` marker, never metadata. So that branch is unreachable except by content collision, which I confirmed: a 2001-line file whose first line happens to be `File Information for "something"`, read with no flag and no line range, now renders `(metadata only)` / `Total lines: 2,001` and swallows the truncation notice.

```ts
const isMetadataOnly =
	(args.metadata_only ?? false) &&
	(result?.startsWith('File Information for') ?? false);
```

That also makes the `!args.start_line && !args.end_line` guard unnecessary. The handler checks `metadata_only` first and ignores line ranges, so `{metadata_only: true, start_line: 5}` currently renders `Lines: 5 - 100` / `Tokens: ~107`, where the token count is of the metadata blob rather than the file.

**2. #970 is only half fixed: directory metadata reads still render as content reads.**

`read_file` with `metadata_only: true` on a directory passes the validator and the handler returns valid metadata, but `getCachedFileContent` throws `EISDIR` in the formatter, the `catch` at `read-file.tsx:365` resets `fileInfo` to defaults, and the user sees:

```
Lines: 1 - 0
Tokens: ~0
```

`isMetadataOnly` is still always false there, which is the symptom the issue reports. Computing `isMetadataOnly` from `args` outside the try block that needs file content fixes it, leaving `totalLines`/`tokens` at zero when the content read fails. Same applies to files the handler reports as `Readable: no`.

Minor, non-blocking:

- A test for the directory case and one asserting that a plain large-file read still shows the truncation display would lock both of the above in.
- The commit subject (`Hi, Jules here! ...`) does not follow the repo's conventional commit format. Happy to squash-merge with a rewritten subject if you'd rather not amend.

