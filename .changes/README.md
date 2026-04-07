# Release fragments

Each user-facing PR should add one file under `.changes/`.

Format:

```md
patch

- Short user-facing note.
- Another note if needed.
```

The first non-empty line must be one of:

- `patch`
- `minor`
- `major`

Everything after that line is folded into the next release section in `CHANGES.md`.

When the release PR workflow runs, it:

1. computes the next version from all pending fragments,
2. prepends a new section to `CHANGES.md`,
3. removes the consumed fragment files,
4. opens or updates a `release: vX.Y.Z` pull request.
