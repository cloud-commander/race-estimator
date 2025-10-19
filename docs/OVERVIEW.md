Race Estimator docs — Overview

This folder contains focused documentation for the Race Estimator data field. Use this overview to find the right document quickly.

Canonical documents

- DEVELOPER_KEY.md — How to securely store and use your Connect IQ developer key (local + CI guidance)
- FIT_ANOMALY_DETECTION.md — Technical deep dive: detection algorithms, code snippets, tuning
- SIMULATOR_TIME_SKIP_TESTING.md — Practical simulator tests and expected behavior
- TIME_SKIP_FIX.md — Implementation notes for time-skip handling in the codebase
- DEBUG_ANALYSIS.md — Debugging tips, CSV vs runtime validation, and tools used
- DEPLOYMENT_SUMMARY.md — Rollout checklist, validation results, and impact analysis
- CHANGES_SUMMARY.md — High-level change log

Quick start

1. Read `DEVELOPER_KEY.md` and ensure your key is available at `~/.Garmin/ConnectIQ/developer_key.der` with `chmod 600`.
2. For debugging and analysis read `DEBUG_ANALYSIS.md`.
3. Run the validation tests in `validate_fit_anomaly_detection.py` to validate anomalous cases.

If you maintain or expand the docs, keep the files focused and cross-reference other docs instead of duplicating content.
