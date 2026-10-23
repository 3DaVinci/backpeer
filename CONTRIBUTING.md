# Contributing

Thanks for taking a look. The project is small and at an early stage, so the
most useful contributions right now are bug reports, review of the crypto and
the protocol code, and pull requests that come with a test.

## Getting started

```sh
fvm install          # Flutter and Dart from .fvmrc
lefthook install     # git hooks: formatting, analyzer, dependency rule
melos bootstrap      # dependencies of all packages
melos run check      # formatting, analyzer and tests
```

Run `flutter` and `dart` through `fvm flutter ...` and `fvm dart ...`, or add
`.fvm/flutter_sdk/bin` to `PATH`.

## Before opening a pull request

- `melos run check` passes. It runs `dart format`, the analyzer with
  `--fatal-infos`, the "no Flutter in the core" rule and the tests.
- New behaviour comes with a test. Crypto, format and protocol changes come
  with test vectors in `test-vectors/`.
- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/):
  `type(scope): summary`, where the type is one of `feat`, `fix`, `docs`,
  `test`, `refactor`, `perf`, `build`, `ci`, `chore`. The subject is at most
  100 characters, the body explains why.
- Keep changes focused: one topic per pull request.

## Code rules

- `core`, `protocol`, `cli`, `daemon_kit`, `node`, `agent`, `coordinator` and
  `relay` must not depend on Flutter, directly or transitively
  (`melos run check-deps`).
- The core is deliberately plain Dart behind interfaces (`CryptoProvider`,
  `ErasureCoder`, `Transport`), so that the implementation can be replaced
  without touching the formats.
- Third-party dependencies must be permissively licensed (MIT, BSD, Apache-2.0,
  ISC, Zlib and the like). LGPL and copyleft dependencies are decided
  case by case and are not accepted without prior discussion.

## Language

Code, comments and commit messages are currently in Russian, and the public
files are in English. Issues and pull requests may be written in English or
Russian; there is no need to translate anything to report a problem.

## License of contributions

By submitting a pull request you agree that your contribution is licensed under
the GNU Affero General Public License v3.0 or later, the same license as the
project. There is no contributor license agreement to sign.

## Security

Please do not open a public issue for a vulnerability. Write to the maintainer
directly (see the commit metadata in the repository) and give us time to fix it
before disclosure.
