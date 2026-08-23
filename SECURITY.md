# Security policy

Do not report WhaleX application vulnerabilities in a public Issue or pull
request. This repository intentionally accepts no application source code.

The CI workflow:

- runs only from the trusted default-branch workflow through schedule,
  `workflow_dispatch`, or `repository_dispatch`;
- accepts only an exact 40-character source commit SHA;
- uses a deploy key that can only read `Yvictor/whalex`;
- removes the key, known-hosts file, and Git remote before tests execute;
- never uploads the private checkout, test coverage, caches, or source-derived
  artifacts;
- publishes only a sanitized CI manifest containing the source SHA, run URL,
  timestamp, and suite result.

