# Repository instructions

- All changes go through a pull request and code-owner approval. Do not directly push to main, merge without approval, force-push protected branches, or weaken repository protections.
- Keep input handling limited to activity timing. Do not read/store keyboard text or key codes, record audio, or add telemetry without an explicitly approved design.
- Preserve the established pet artwork and behavior unless the task explicitly requests changes.
- Run ./scripts/test.sh for Swift changes; visually verify rendering changes on macOS.
- Update README.md for behavior, setup, permission, or control changes.
- Never commit build/, personal diagnostics, secrets, or temporary files.
- Preserve author GOPAL GOYAL and co-author SAKSHAM BATTA credits.
