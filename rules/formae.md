- Every PR must reference and close an open issue (`Fixes #N`) - PRs without a
  linked issue are closed without review.
- Every file needs the REUSE headers:
  `// © 2025 Platform Engineering Labs Inc.`
  `// SPDX-License-Identifier: FSL-1.1-ALv2`
  (run `make add-license` to add them idempotently).
- Squash-merge titles follow Conventional Commits: `fix(<scope>): ...` /
  `feat(<scope>): ...`.
- Go style via golangci-lint; run `go build ./...` and `go vet ./...`.
- Feature work must come from a maintainer-created issue; stick to bug/contained
  fixes on existing good-first-issue issues.
- The repository owner must have signed the CLA before this PR can merge.
