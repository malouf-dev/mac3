# Local audit and portable build path

This is a binary distribution, not source code, so it cannot be proven safe by
inspection alone. The former installer downloaded mutable GitHub files and ran
a bundled signing executable.

`make-mac3-app.sh` makes no network requests. It packages the local engine
archive and signs the Launcher with macOS `codesign`:

```text
mac3-macos-arm64.tar.gz
7c1a04fba5e95882a20a6fdddc17f5cccbe43eb443b750b2b001dddf19ce705e
```

The output is ad-hoc signed and not Apple-notarized. After first setup, it is
portable: the internal engine holds the game data and streamed audio inside the
outer mac3.app.

## mac3 update behavior

mac3 makes no network request unless **Check for Updates** is selected. An
explicit **Install** must match the SHA-256 declared by the fetched manifest,
then is cached inside mac3.app and used to rebuild its internal engine.

The opaque native engine contains an old updater that can launch the upstream
Terminal installer. mac3 replaces that fixed-size version-check command with a
local `true` command, then ad-hoc re-signs both the engine and portable outer
app. A changed engine layout fails the build rather than silently using the
old updater.

The checksum guards against accidental corruption, but it is not a release
signature: the manifest and archive currently come from the same GitHub fork.
A production channel should verify a manifest signed by a separately held key.
