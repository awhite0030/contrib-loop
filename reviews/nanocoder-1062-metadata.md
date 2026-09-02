Reviewer (will-lamerton) CHANGES_REQUESTED. Blocking items:

1. Drop the totalLines > FILE_READ_PREVIEW_THRESHOLD_LINES disjunct. There is no auto-fallback to metadata for large files: "File Information for" is emitted at read-file.tsx:48 only inside if (args.metadata_only). A large file read without the flag returns a 250-line preview plus a [Truncated at line ...] marker, never metadata. The disjunct only triggers by content collision. Replace with:
   const isMetadataOnly = (args.metadata_only ?? false) && (result?.startsWith("File Information for") ?? false);
   This also makes the !args.start_line && !args.end_line guard unnecessary since metadata_only ignores line ranges, so {metadata_only: true, start_line: 5} currently renders "Lines: 5 - 100" / "Tokens: ~107" where the token count is of the metadata blob rather than the file.

2. #970 is only half fixed: directory metadata reads still render as content reads. metadata_only: true on a directory passes the validator and the handler returns valid metadata, but getCachedFileContent throws EISDIR in the formatter; the catch at read-file.tsx:365 resets fileInfo to defaults and user sees "Lines: 1 - 0, Tokens: ~0". isMetadataOnly is still always false there. Computing isMetadataOnly from args OUTSIDE the try block that needs file content fixes it, leaving totalLines/tokens at zero when content read fails. Same for files the handler reports as "Readable: no".

Also (non-blocking but expected): add a test for the directory case and one asserting that a plain large-file read still shows the truncation display. Commit subject should follow the repo's conventional commit format (e.g. fix(nanocoder): ...).
