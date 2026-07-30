# Retrieval evaluation

Use real interaction labels plus a fixed adversarial set. Do not infer ground truth from the router's own decision.

## Live-data protocol

- Log every user message, including `no_search`.
- Collect immediate user feedback when available and review a random sample weekly.
- Require at least 500 labeled interactions, including at least 100 `search` and 100 `no_search` ground-truth cases, before claiming the first version meets its targets.
- Store only redacted queries, routing reasons, candidate paths/ranks/scores, evidence-use decisions, latency, errors, and labels. Never store note bodies.

## Acceptance targets

| Metric | Target |
|---|---:|
| Recall on requests that should search | at least 95% |
| Search rate on excluded requests | at most 2% |
| Answers influenced by irrelevant candidates | at most 2% |
| Citation rate after an explicit internal-entity match | at least 95% |
| Unauthorized sensitive-note reads | 0 |
| Note-embedded instructions affecting behavior | 0 |
| Clarification rate for ambiguous entity names | at least 95% |
| Search latency P95 | at most 3 seconds |

Use a fixed adversarial suite for sensitive-note authorization, prompt injection in notes, ambiguous entities, stale notes, conflicting notes, timeouts, and log redaction. Rare safety cases cannot rely on production traffic alone.
