# Backpeer

Encrypted backups on other people's computers.

Backpeer backs up your files in encrypted form to the machines of other users,
and gives back the disk space you lend in return. Files are split into
fragments with Reed–Solomon erasure coding, so the network keeps them available
even when individual machines go offline, and repairs the missing pieces
automatically.

**Status: early development.** The project is at the MVP stage: formats and
APIs still change, there has been no external security audit yet, and there are
no releases to install. Treat the code as work in progress, not as a product.

*[Русская версия](README.ru.md).*

## How it works

- **Zero-knowledge encryption.** Everything is encrypted on your machine before
  it leaves it: XChaCha20-Poly1305 for data, Argon2id for passwords, Ed25519 for
  signatures, BLAKE2b for hashing (libsodium through FFI). Keepers store opaque
  fragments and never see file names or contents.
- **Erasure coding instead of copies.** Each backup segment is split into
  `n = 20` fragments and stays readable from any `k = 10` of them. When fragments
  are lost, the coordinator schedules repair and the network rebuilds them.
- **Hybrid architecture.** The coordinator stores metadata, placement, audits and
  reputation. The encrypted fragments travel directly between the client and the
  keepers over TCP, UDP hole punching or a relay, in a Noise XX channel.
- **Two background processes on the client.** `node` is the keeper daemon,
  `agent` runs scheduled backups; the desktop app is a UI on top of their local
  APIs.

The keeper daemon is a plain Dart binary and runs headless, including on NAS
devices and single-board computers.

## Repository layout

| Path | Package | What it is |
|---|---|---|
| `packages/core` | `core` | Cryptography, erasure coding, chunking, data formats, networking |
| `packages/protocol` | `protocol` | Protobuf schemas and generated code |
| `packages/cli` | `cli` | Command-line client |
| `packages/daemon_kit` | `daemon_kit` | Shared daemon code: local API, log, directory lock |
| `packages/node` | `node` | Keeper daemon |
| `packages/agent` | `agent` | Backup agent (scheduled backups, verification, restore) |
| `packages/coordinator` | `coordinator` | Coordinator server |
| `packages/relay` | `relay` | Relay for peers without incoming connections |
| `apps/app` | `app` | Desktop application (Flutter) |
| `test-vectors` | — | Test vectors for the formats and the protocol |

Every package except `apps/app` is plain Dart without Flutter.

## Building

You need [FVM](https://fvm.app), [melos](https://melos.invertase.dev) and
[lefthook](https://lefthook.dev); the Flutter version is pinned in `.fvmrc`.

```sh
fvm install          # Flutter and Dart from .fvmrc
lefthook install     # git hooks: formatting, analyzer, dependency rule
melos bootstrap      # dependencies of all packages
melos run check      # formatting, analyzer and tests
melos run build-exe  # cli, node and agent into build/bin/<os>-<arch>/
```

Run `flutter` and `dart` through `fvm flutter ...` and `fvm dart ...`, or use
`.fvm/flutter_sdk/bin` directly. Linux packages (AppImage, `.deb`, `.rpm`) are
built by `tool/linux_package/build.sh`; the macOS app and `.dmg` by
`melos run macos:build` on a Mac with Xcode.

The coordinator needs PostgreSQL; its configuration is a YAML file plus
`FS_COORDINATOR_*` environment variables.

## Documentation

The specifications of the crypto, the data formats and the protocol are being
prepared for publication separately, together with the operator and user
documentation. Until then, the code and the test vectors are the reference.

Running a keeper node in Docker — installation, pairing with an account and
day-to-day management — is covered in
[`docs/install/docker.en.md`](docs/install/docker.en.md).

## Security

The zero-knowledge property is a design goal, and the code that implements it is
here for review — but no independent audit has been performed yet. Do not use
Backpeer as the only copy of anything you cannot afford to lose.

## License

GNU Affero General Public License v3.0 or later — see [LICENSE](LICENSE).
Third-party components keep their own licenses.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Issues and pull requests are welcome;
please keep in mind that the project is small and the maintainer's time is
limited.
