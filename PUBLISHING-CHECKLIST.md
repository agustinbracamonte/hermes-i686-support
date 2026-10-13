# Public repository pre-publication checklist

- Source/documentation license: MIT is present; reconcile all third-party notices against exact versions before release.
- Run `scripts/publication-audit.sh`; this scans all worktree files (including ignored/untracked), ref history, commit metadata, and unreachable blobs. Treat every flag as a stop condition and do not expose matched values.
- Run `tests/test-scripts.sh` and `tests/test-signal-cli-integration.sh`.
- Confirm `git ls-files` contains no binaries, local configuration, credentials, sessions, databases, logs, or build outputs.
- Create ZIP/source release only from a reviewed commit with `git archive`; do not include ignored staging or vendor trees.
- Binary wheel collection is separate and requires an explicit approval manifest with exact version/name and SHA-256; the verifier enforces metadata, i386 ELF, extension, and dynamic dependency profile.
- Signal CLI remains experimental. Do not publish or collect any Signal JAR, JNI library, or native binary until clean rebuild, corresponding source, SBOM and GPL/AGPL notice obligations are complete.
- A passed local audit does not authorize GitHub repository creation, push, tags, Releases, or publication. Obtain explicit approval for those actions.
