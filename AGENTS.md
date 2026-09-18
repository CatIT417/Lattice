# Lattice

Lattice is a native outliner for iOS and macOS, inspired by Roam Research. Pages and nested paragraphs are blocks. Page links (`[[Title]]`), block references (`((uuid))`), and tags connect them.

The app stores data locally in SQLite and synchronizes it through CloudKit. It uses SwiftUI, UIKit/AppKit for text editing, SQLiteData over GRDB, Dependencies for dependency injection, and NavigationKit for routing. Tests use Swift Testing.

## Where to start

| Area | Entry points |
| --- | --- |
| App startup | `src/App.swift`, `src/Extensions/DependencyValues+database.swift` |
| Database setup and behavior | `src/Database/Database.swift`, then `Migrations/`, `Views/`, `Triggers/`, and `Maintenance/` in that directory |
| Data models | `src/Models/` |
| Screens and block rendering | `src/Views/Pages/`, `src/Views/Components/` |
| Shared UI state and coordination | `src/ViewModels/` |
| Routes and deep links | `src/Support/Navigation.swift` |
| Parsing, ordering, import, and export | `src/Support/` |
| Tests | `tests/`, organized by source area |

## Database model

`blocks` is the only synchronized table. A block has a page title or paragraph text. `parentId` defines the hierarchy; page membership is derived. `deletedAt` marks explicit deletion, and `mergedInto` identifies a page redirect. Other tables and indexes are local.

Use `Page`, `Paragraph`, and `Backlink` views for normal reads, or filter `Block` with `isVisible`. Raw rows can contain deleted blocks, redirects, or unresolved structure. Missing parents and cycles remain stored but hidden. Insert and delete through `Page` or `Paragraph`; update primary fields through `Block`.

Triggers maintain hierarchy, references, and search indexes in the write transaction. These indexes must also update during remote sync. Local actions, such as creating linked pages or rewriting references after a rename, must respect `SyncEngine.isSynchronizing`. Keep synchronized writes out of tasks started inside triggers.

Use `(order, id)` for sibling order and `ParagraphOrder` for rank changes. Equal ranks are valid. `MergeDuplicatePages` handles duplicate pages and redirects after sync transactions. Construct `SyncEngine` before maintenance. Use `DayOfYear` for daily-note title and date rules.

## Text editing and navigation

`src/Views/Components/EditableText/` contains the shared editor and separate UIKit/AppKit implementations. It displays rendered links when idle and raw syntax during editing. `AttributedStringBuilder` builds the rendered text and maps cursor positions. All editor offsets use **UTF-16 code units**, as `NSRange` does; do not use `String.count` for these offsets.

`BlockCoordinator` manages focus requests through Dependencies. `InlineParser` and `String.extractRefs()` handle inline syntax and references. NavigationKit uses typed `Destination` values and `lattice://` deep links.

## Working on the code

- Follow nearby patterns. Views commonly use `@FetchAll` and `@FetchOne` to observe database queries.
- Use the `pfw-structured-queries` skill for typed queries and `pfw-sqlite-data` for database fetching guidance.
- If you need to test a specific snippet of code, use `mcp__xcode__ExecuteSnippet` to run it in the context of a specific file (with access to `fileprivate` declarations).
- Use the `mcp__xcode__DocumentationSearch` tool to search Apple Developer Documentation, and `mcp__sosumi__fetchAppleDocumentation` to fetch specific pages. You may also use the `library-docs` skill if you need extra info on how third-party libraries work.
- Prefer Xcode MCP for builds, tests, and previews. Always use the **`LatticeDev` scheme** for tests; `Lattice` is for production. Build and run tests after code changes.
- Check both platform implementations when changing editor behavior. Shut down any simulator you start when verification is complete.
