# Contributing to patchelf.rb

Thank you for helping improve `patchelf.rb`.

## Set up the repository

Install Ruby 3.3 or newer and Bundler, then install the locked dependencies:

```console
bundle install
```

Run the same repository-owned checks used by CI:

```console
bundle exec rake
```

That command runs RuboCop, the complete RSpec suite, YARD documentation checks,
and a build-and-smoke test of the packaged gem. Complete suite runs enforce
minimum line and branch coverage percentages. Focused spec runs still generate
coverage reports, but do not apply repository-wide minimums.

Useful focused commands are:

```console
bundle exec rspec
bundle exec rspec spec/patcher_spec.rb
bundle exec rubocop
bundle exec rake doc
bundle exec rake build
```

The suite can inspect ELF files on macOS, but tests that execute patched ELF
binaries are Linux-only and are reported as pending elsewhere. CI runs both
platforms. A change affecting executable layout should be verified on Linux.

## Submit a change

- Add a focused regression test for behavior changes and bug fixes.
- Keep public behavior and limitations documented in `README.md` and YARD
  comments.
- Keep commits focused and include a `Signed-off-by` trailer. `git commit -s`
  adds it automatically.
- Run `bundle exec rake` before opening a pull request.

The README is intentionally static. Update it directly when public behavior
changes.

## Test fixtures

ELF fixtures live in `spec/files`. Prefer a small, source-generated reproducer
over copying a production executable.

Any new or replaced binary fixture must include:

- the smallest practical source or deterministic generation recipe;
- the upstream source and version, when applicable;
- a SHA-256 digest for externally built artifacts;
- the reason the fixture is necessary and the spec that exercises it; and
- its license and attribution requirements.

Update both `spec/files/README.md` and `THIRD_PARTY_NOTICES.md` when third-party
fixture provenance changes. Do not regenerate committed fixtures casually: ELF
layout varies with compiler and linker versions, so review the resulting binary
diff and run the full Linux suite.

## Reporting problems

Use [GitHub Issues](https://github.com/Homebrew/patchelf.rb/issues) for ordinary
bugs. Report suspected vulnerabilities privately through
[GitHub's security advisory form](https://github.com/Homebrew/patchelf.rb/security/advisories/new)
and follow [Homebrew's security policy](https://github.com/Homebrew/.github/security/policy).
