# Repository Guidelines

This is the native SwiftUI Sub2 Mobile project. Work in the existing checkout and branch; do not create a worktree unless the user asks.

<!-- CODEGRAPH_START -->
## CodeGraph

When `.codegraph/` exists at the repository root, use CodeGraph before searching or reading code to locate or understand symbols:

- MCP: call `codegraph_explore` with `projectPath` set to this checkout's absolute path. Name a symbol or source file to retrieve its current line-numbered source and caller relationships.
- CLI: run `codegraph explore "DashboardStats"` from this repository root.
- If a response flags stale files, run `codegraph sync` and query again; if freshness cannot be confirmed, read the flagged files directly.
- If the index is missing, use normal file tools. Initialize it only when the user authorizes indexing.

The user has authorized CodeGraph for this project. To initialize another checkout, run `codegraph init --yes`; use `codegraph sync` after source changes and `codegraph status` to inspect index freshness. `.codegraph/` is local generated data ignored by Git. Existing `.gitignore` rules exclude build products and signing material from the scan.
<!-- CODEGRAPH_END -->
