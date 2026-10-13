# Signal i386 patch set

These patches were recovered from the validated local build and are intentionally version-bound.

| Patch | Upstream base | License governing patch/source | SHA-256 |
|---|---|---|---|
| `signal-cli-v0.14.9-java21-i386.patch` | signal-cli `v0.14.9` | GPL-3.0-only | `65324d5d5dfd40f7392fd05a7f57a53927c0742bd1815c0156cc3ef7cc581e4d` |
| `libsignal-v0.103.0-i386-protobuf-root.patch` | libsignal `v0.103.0` | AGPL-3.0-only | `0effc12567d12d6137e6a97a231b3af7d39feb6745264487692d38c4ed882215` |

## Apply only in clean checkouts

```bash
git -C PATH_TO_SIGNAL_CLI apply --check PATH_TO_PATCH
# Apply only after the check succeeds.
git -C PATH_TO_SIGNAL_CLI apply PATH_TO_PATCH
```

The Signal patch enables a Java 21/i386-compatible build and the libsignal patch corrects the protobuf include root used by the pinned revision. They are not general upstream patches and must not be force-applied to newer revisions.

## License and source obligations

The patch files are derivative works governed by their upstream GPL-3.0-only / AGPL-3.0-only terms, not this repository's MIT license. Anyone distributing a modified binary must make the complete corresponding source, these exact patches, build scripts and required notices available under the applicable terms.
