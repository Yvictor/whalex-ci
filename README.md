# WhaleX public CI and releases

This repository contains only the public CI orchestrator, CI evidence, and
sanitized WhaleX release notes. The application source remains in the private
`Yvictor/whalex` repository and is never committed or uploaded as an artifact
here.

CI checks out one exact private commit with a dedicated read-only deploy key.
The key and Git remote are removed before any project command runs. Successful
runs publish a small evidence release named `ci-<40-character-source-sha>`.

Public release notes are published from reviewed Markdown files in the private
repository after the corresponding immutable Production version is live.
The publishing workflow verifies the exact public CI evidence and live
Production SHA/tag, copies only that single reviewed Markdown file, and uploads
no source, build output, history, diff, cache, or deployment documentation.

See the private repository's deployment runbook for operator procedures,
credential rotation, Staging promotion, Production release, and rollback.
