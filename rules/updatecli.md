- Conventional Commits for PR titles: `fix(<scope>): <short summary>`
  (scope = plugin/package name, e.g. fix(autodiscovery/helmfile)).
- Add `Signed-off-by:` to your commit (`git commit --signoff`) - project convention.
- PR body should start with `Fix #<issue>` followed by a "Test" section listing
  how the change was tested.
- Plugin docs are generated from Go doc comments on Spec fields: keep doc
  comments on changed Spec fields accurate.
- Unit tests must run offline (use mocks; tests run with -short).
