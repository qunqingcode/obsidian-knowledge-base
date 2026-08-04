# Graph Query Reference

Use graph modes for questions about `[[wikilinks]]`, backlinks, note relationships, paths, hubs, clusters, or vault health.

For ordinary knowledge questions, start with `vault.ps1 -Mode context`. It searches
first and then expands one-hop links from the strongest hits. Use the specialized
commands below when the user explicitly asks about structure or relationships.

## Command map

| Mode | Required parameters | Purpose |
|---|---|---|
| `links` | `-Note` | Outgoing links |
| `backlinks` | `-Note` | Incoming links |
| `neighbors` | `-Note`, optional `-Depth 1..5` | Undirected N-hop neighborhood with direct-edge evidence |
| `path` | `-From`, `-To` | BFS shortest path with edge direction and evidence |
| `cluster` | `-Note` | Full connected component |
| `bridges` | none | Iterative Tarjan bridge edges and articulation points |
| `hubs` | optional `-Top`, `-Folder` | Highest in/out/total degree notes |
| `orphans` | optional `-Folder` | Notes with no incoming or outgoing links |
| `relations` | `-Note` | Frontmatter relations, inline Dataview relations, links, backlinks |
| `stats` | none | Vault-wide graph statistics |
| `unresolved` | none | Unresolved wikilinks and Markdown note links |
| `suggest-links` | optional `-MaxSuggestions` | Frontmatter-based orphan rescue and common-neighbor/Jaccard missing-link candidates |
| `health` | none | KPIs, structural risks, and suggestions |
| `report` | optional `-Top`, `-Folder` | Combined stats, hubs, bridges, orphans, and health data |

Examples:

```powershell
.\scripts\vault.ps1 -Mode backlinks -Note "示例文档.md"
.\scripts\vault.ps1 -Mode neighbors -Note "示例文档.md" -Depth 2
.\scripts\vault.ps1 -Mode path -From "示例文档.md" -To "示例文档2.md"
.\scripts\vault.ps1 -Mode hubs -Top 10
.\scripts\vault.ps1 -Mode health
```

## Backends

- `auto` prefers the live Obsidian metadata cache and falls back to local vault parsing.
- `obsidian` requires Obsidian running and its CLI enabled. It reads `app.metadataCache.resolvedLinks`, `unresolvedLinks`, cached frontmatter, and link positions.
- `files` works without Obsidian. It resolves wikilinks, aliases, relative Markdown links, embeds, headings, and frontmatter relation fields from the configured vault.

Use `-Backend obsidian` only when the request specifically requires the live Obsidian cache. Use `auto` normally.

## Relationship reasoning

Prioritize evidence in this order:

1. Frontmatter relationship fields such as `Up`, `来源`, or `参考`.
2. Inline Dataview relations such as `[Up:: [[主题索引]]]`.
3. Link direction and the sentence surrounding the link.
4. LLM inference after reading both notes.

Label inferred relationships explicitly and include confidence. Never present a structural path as proof of a semantic claim without reading the relevant notes.

## Health interpretation

The `health` mode follows these thresholds:

| KPI | Green | Yellow | Red |
|---|---:|---:|---:|
| Orphan ratio | `<10%` | `10–25%` | `>25%` |
| Largest component coverage | `>80%` | `50–80%` | `<50%` |
| Average outgoing links/note | `>3.0` | `1.5–3.0` | `<1.5` |
| Cross-folder link ratio | `>20%` | `10–20%` | `<10%` |
| Articulation-point ratio | `<5%` | `5–15%` | `>15%` |
| Out-only note ratio | `<5%` | `5–15%` | `>15%` |

Treat suggestions as review candidates, never as authorization to edit notes.
