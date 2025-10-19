Developer Key (recommended best practice)

This repository does NOT include a developer key. For consistent local builds and simulator runs, use a single canonical, secure location on your machine:

~/.Garmin/ConnectIQ/developer_key.der

Why this location?

- The Connect IQ toolchain examples and CI snippets typically reference `~/.Garmin/ConnectIQ/developer_key.der`. Using that location avoids per-repo duplication and accidental commits.

Recommended local setup

1. Create the directory (if missing) and copy your downloaded key there:

```bash
mkdir -p ~/.Garmin/ConnectIQ
cp /path/to/downloaded/developer_key.der ~/.Garmin/ConnectIQ/developer_key.der
```

2. Restrict access to the key file:

```bash
chmod 600 ~/.Garmin/ConnectIQ/developer_key.der
```

3. Add local patterns to `.gitignore` so keys are never committed (project root):

```
developer_key
*.der
*.pem
```

Editor / VS Code

- If you use the Monkey C extension or workspace settings, point `monkeyC.developerKeyPath` to the canonical path (absolute or `~` expanded by your shell):

```jsonc
{
  "monkeyC.developerKeyPath": "/Users/<youruser>/.Garmin/ConnectIQ/developer_key.der"
}
```

Build command example

```bash
monkeyc -o bin/RaceEstimator.prg -f monkey.jungle -y ~/.Garmin/ConnectIQ/developer_key.der -d fenix7
```

CI / Automated Builds

- Never store the raw private key in the repository. Use your CI provider's secret store (GitHub Actions secrets, GitLab CI variables, etc.).
- At build time, write the secret into the runner's filesystem and restrict permissions, then run the build and securely delete the key.

Example (GitHub Actions snippet)

```yaml
- name: Restore developer key
  run: |
    mkdir -p ~/.Garmin/ConnectIQ
    echo "$DEVELOPER_KEY_BASE64" | base64 --decode > ~/.Garmin/ConnectIQ/developer_key.der
    chmod 600 ~/.Garmin/ConnectIQ/developer_key.der
  env:
    DEVELOPER_KEY_BASE64: ${{ secrets.DEVELOPER_KEY_BASE64 }}

- name: Build
  run: |
    monkeyc -o bin/RaceEstimator.prg -f monkey.jungle -y ~/.Garmin/ConnectIQ/developer_key.der -d fenix7

- name: Clean up
  run: |
    shred -u ~/.Garmin/ConnectIQ/developer_key.der || rm -f ~/.Garmin/ConnectIQ/developer_key.der
```

Notes

- Do NOT commit keys or secrets. Treat them like passwords.
- If you suspect a key has been exposed, revoke and rotate it immediately.
