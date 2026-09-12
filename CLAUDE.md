# Lattice

A Roam Research-style outliner app for iOS and macOS built with SwiftUI and SQLite.

## Project Vision

Lattice is a personal knowledge management tool inspired by Roam Research's outliner paradigm:

- **Hierarchical blocks**: Everything is a block that can contain other blocks
- **Bidirectional linking**: `[[Page Links]]`, `((block refs))`, and `#tags` create a knowledge graph
- **Pages as entry points**: Pages are just blocks with titles instead of text content
- **Recursive structure**: Blocks can nest infinitely deep

## Tech Stack

- **SwiftUI** for UI
- **Swift Testing** - Unit tests
- **SQLiteData** - Type-safe GRDB wrapper with macros
- **Dependencies** - Pointfree-style dependency injection
- **NavigationKit** - Custom navigation library for routing

Use the `mcp__xcode__DocumentationSearch` tool to search Apple Developer Documentation, and `mcp__sosumi__fetchAppleDocumentation` to fetch specific pages.
You may also use the `library-docs` skill if you need extra info on how third-party libraries work.

## Database Architecture

`blocks` is the only synchronized table. A block has either a title or paragraph text. `parentId` is the only stored source of page membership. `order` is an integer rank. `deletedAt` records explicit deletion, and `mergedInto` records a page redirect.

The physical `pageId` and `position` columns remain for the shipped schema. They are absent from `Block` and have no authority. Raw SQL must name model columns with `Block.columns`. Do not use `SELECT *` or `RETURNING *` for a model query.

There are no foreign keys. A child can arrive before its parent. Missing parents and cycles leave raw rows stored and hidden until their structure resolves.

### Local tables and views

- `blockAncestors` stores ancestor relationships up to the page root.
- `blockHierarchy` caches each block's containing page and effective visibility. It follows page redirects and has an index on `(pageId, isVisible)`.
- `blockReferences` stores source IDs, reference kinds, and unresolved title, date, or UUID keys. The kind selects page or UUID lookup; there is no separate target type. Targets need not exist. `(sourceBlockId, kind, targetKey)` removes repeated references of the same kind.
- `blockTexts` indexes raw titles and paragraph text for search.
- `linkMetadata` caches link previews.
- `Page` shows live pages and excludes redirects.
- `Paragraph` joins `blockHierarchy`, exposes derived `pageId`, and shows only visible paragraphs. A direct child of a redirect exposes the final page as its parent while maintenance moves the raw relationship.
- `Backlink` resolves reference keys against visible targets and visible sources. Block references and embeds resolve only paragraph IDs through the `Paragraph` view.

Normal screens, search, exports, and reference queries use visible views or `Block.isVisible`. Raw rows are for maintenance and explicit restoration.

### Writes and triggers

Insert and delete through `Page` or `Paragraph`. Update primary fields through `Block`. View deletion sets a marker on the explicit root. It does not mark descendants. A move to a live parent removes inherited deletion. A child's own marker remains effective.

- `SyncAncestorsTable` maintains ancestors and hierarchy in the same transaction. It uses raw rows and follows affected redirect chains. It also handles late parents and physical deletion. Its update trigger rebuilds affected hierarchy first, then updates the edited block and cached containing page timestamps for local edits. Text and formatting edits use the cache without a rebuild.
- `SyncReferencesTable` indexes text on local and remote writes. Only local writes create missing linked pages or rewrite text for a page rename. A local rename calls the shared `MergeDuplicatePages.merge` operation to join known live copies of the old title under the smallest ID before rewriting references. Deletion preserves link text.
- `SyncBlocksFTSTable` maintains the raw text index for local and remote writes.
- `SafetyChecks` rejects local moves under the same block or its descendants.
- `CleanupDerivedRows` removes reference keys when their source is physically deleted. Missing target keys remain.

A failed index update must fail the write. The SQL callback functions are instance methods on the trigger structs. This avoids the pinned macro's missing `try` in generated wrappers for free functions.

Remote writes run with `SyncEngine.isSynchronizing`. Derived indexes run in that state. Page creation, rename rewriting, timestamp changes, and local move validation do not. Use `SyncEngine.$isSynchronizing` in SQL trigger conditions. Do not start tasks inside triggers to perform synchronized writes.

### Ordering and maintenance

Use `(order, id)` for sibling order. Equal ranks are valid. `ParagraphOrder` reads adjacent IDs and ranks in the edit transaction. It loads the full sequence only if there is no gap or an endpoint would overflow, then renumbers that sibling group. It keeps hidden children in the raw sequence. Remote writes never renumber. Rank-only lookups use one query across raw parent IDs. Visible navigation queries each parent separately and uses the `(parentId, order, id)` index. Editor moves are one sibling up or down. Numbered bullets and navigation use the displayed sibling index.

`MergeDuplicatePages` selects the smallest live page ID for duplicate titles or daily dates. It keeps losing rows as redirects and moves direct children only. It also handles children that arrive under a known redirect later. Deleted pages do not enter merges. Repeated maintenance with no pending work makes no writes.

Review finding 1 remains open: an automatic child move can remove a deleted redirect ancestor, including before its deletion marker arrives. The owner deferred changes to reparenting and future safe cleanup. Do not claim that this race is fixed.

Construct `SyncEngine` before running maintenance. `DuplicatePagesWatcher` observes pending merge or redirect work and runs the worker after commit, outside the sync state.

Valid `YYYY-MM-DD` titles and the supported long date titles are reserved for daily notes. `DayOfYear` accepts both forms and rejects invalid dates. Page creation, rename validation, imports, and reference parsing use this rule.

Creating a deleted title or daily date again makes a new empty page. It does not clear the old marker. Deterministic first daily-note IDs and explicit Undo UI remain phase 3 work. Physical garbage collection remains future work.

Keep database backups, sync health reporting, and diagnostics. The CloudKit data migration is complete. The old cutover script is historical; do not run it on this schema.

## Key Patterns

### Type-Safe Queries with SQLiteData

> Use the `pfw-structured-queries` skill when you need to write type-safe queries.

```swift
// Fetch children of a block
Paragraph.where { $0.parentId == blockId }.order { ($0.order, $0.id) }

// Fetch ancestors ordered root-first
Ancestor.where { $0.blockId == blockId }
    .order { $0.depth.desc() }
    .join(Block.all) { $0.ancestorId.eq($1.id) }
```

### @FetchAll / @FetchOne Property Wrappers

> Use the `pfw-sqlite-data` skill when you need help with data fetching

```swift
struct BlockView: View {
    @FetchOne var block: Paragraph?
    @FetchAll var children: [Paragraph]

    init(blockId: Block.ID) {
        _block = FetchOne(Paragraph.find(blockId))
        _children = FetchAll(Paragraph.where { $0.parentId == blockId }.order { ($0.order, $0.id) })
    }
}
```

### HasChildren Protocol

Models conforming to `HasChildren` get efficient child-loading:

```swift
Page.withChildren(id: pageId) // (see `Table+withChildren.swift`)
```

### Reference Extraction

`String.extractRefs()` parses inline syntax and returns `TextRef` structs:

- `#tag` or `#[[tag]]` → `.tag`
- `[[Page Links]]` → `.pageLink`
- `((valid-uuid))` → `.blockRef`

Each `TextRef` has a `.url` for navigation. Reference indexing stores its target key. The backlink view resolves that key when read.

### BlockCoordinator (Focus Management)

`BlockCoordinator` lets you queue focus changes for a block's `EditableText`:

```swift
@Environment(\.blockCoordinator) var coordinator

// Push-only (not reactive)
coordinator.isActive(blockId:)  // Currently focused block ID
coordinator.cursorPositionFor(blockId:)
coordinator.modeFor(blockId:)   // .raw (editing) or .rendered (viewing)
```

## Navigation

Uses NavigationKit with typed destinations:

```swift
enum Destination.Tabs {
    case daily   // Daily notes view
    case search  // Search screen
}

enum Destination.Pages {
    case page(id: UUID)
    case paragraph(id: UUID)
    case block(id: UUID)  // Resolves the visible page or paragraph, including page redirects
    case pageByTitle(title: String)  // Auto-creates page if it doesn't exist
}

// Usage
NavigationButton(push: .page(id: pageId)) { Text(page.title) }

// or programmatically
@Environment(Router.self) var router
router.navigate(push: .page(id: pageId))
```

### Deeplinks

The app handles deep URLs for navigation from link taps:

```swift
enum Destination.Deeplinks {
    case block(id: UUID)      // lattice://block/{id}
    case tag(name: String)    // lattice://tag/{name}
    case page(title: String)  // lattice://page/{title}
}
```

## Text Editing Architecture

Lattice uses a dual-mode text editor (`EditableText`) that shows rendered links in view mode and raw syntax in edit mode.

### Core Components

```
EditableText (SwiftUI view wrapper)
├── EditableTextView (platform-specific)
│   ├── iOS/visionOS: UIViewRepresentable
│   │   ├── AutosizingTextView (UITextView subclass)
│   │   └── Coordinator (UITextViewDelegate)
│   └── macOS: NSViewRepresentable
│       └── Coordinator (NSTextViewDelegate)
└── AttributedStringBuilder (shared, in Support/)
    ├── IndexMapping (cursor position translation)
    └── buildAttributedString() (parses refs into styled links)
```

### Key Files

- **`Views/Components/EditableText/`** - Directory containing the text editor components:
    - `EditableText.swift` - Main SwiftUI view that wraps platform-specific implementations
    - `EditableText+iOS.swift` - iOS/visionOS implementation with `AutosizingTextView` and `EditableTextView` (UIViewRepresentable)
    - `EditableText+macOS.swift` - macOS implementation with `EditableTextView` (NSViewRepresentable)
    - `EditableText+Shared.swift` - Shared helper functions for bracket auto-completion, auto-deletion, and text wrapping
- **`Support/AttributedStringBuilder.swift`** - Builds NSAttributedString with clickable links and provides index mapping

### View Mode vs Edit Mode

| Mode | Text Display       | Links                    |
| ---- | ------------------ | ------------------------ |
| View | `Hello World!`     | Styled, clickable (blue) |
| Edit | `Hello [[World]]!` | Raw syntax, plain text   |

### How It Works

1. **View mode**: Text is rendered as NSAttributedString with `.link` attributes
2. **On tap**: UITextView/NSTextView gains focus, triggering edit mode
3. **Edit mode transition**:
    - Capture cursor position in rendered text
    - Switch to plain text (raw syntax)
    - Map cursor position using IndexMapping
4. **On focus loss**: Save changes, switch back to rendered mode

### Index Mapping

When transitioning from view → edit mode, cursor positions must be mapped:

```
Rendered: "Hello World!"     (cursor at 8 = 'r')
Raw:      "Hello [[World]]!" (cursor should be at 10 = 'r')
```

`AttributedStringBuilder` produces both the NSAttributedString and an `IndexMapping` that maps each rendered character position to its raw position.

### UTF-16 Indexing

All cursor positions, text offsets, and index mappings in EditableText use **UTF-16 code units** (matching `NSRange`, `NSString.length`, and UIKit/AppKit layout APIs). Never use Swift `String.count` or `String.index(_:offsetBy:)` with offsets from `NSRange.location` — use `(string as NSString).length`, `String.Index(utf16Offset:in:)`, or `string.utf16.count` instead.

### Link Tap Handling

Links use deep URLs (`lattice://page/Title`) that NavigationKit handles:

```swift
// In iOS Coordinator
func textView(_: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
    if case let .link(url) = textItem.content {
        linkWasTapped = true
        return UIAction { [weak self] _ in
            self?.parent.onLinkTap(url)
        }
    }
    return defaultAction
}

// In macOS Coordinator
func textView(_: NSTextView, clickedOnLink link: Any, at _: Int) -> Bool {
    linkWasTapped = true
    if let url = link as? URL {
        parent.onLinkTap(url)
    }
    return true
}
```

The `linkWasTapped` flag prevents the text view from entering edit mode when a link is tapped.

## Database Initialization Order

1. Open SQLite and attach the metadatabase. Register SQL functions and temporary views on each connection. SQLite can define a view before its base tables exist.
2. Run persistent migrations. `CreateReferencesTable` creates the final reference schema directly. `CreateLocalGraphIndexes` creates the hierarchy cache and its indexes. The tables start empty; triggers populate them as blocks arrive.
3. Install the final app triggers on the writer connection.
4. Construct `SyncEngine` for `Block`. This installs sync metadata triggers.
5. Run pending duplicate and redirect maintenance as a local transaction.
6. Start the watcher, retain development seeding, and make the daily backup.

This release requires a one-time local data reset on every device. Synchronize or export all required edits, then reset the local database and sync metadata before opening the new build. Retain CloudKit records. Reinstalling alone is not the reset contract. The revised migrations do not support older local databases. Use new migration identifiers for future changes after this baseline. Test fresh creation and download from CloudKit. A local index rebuild must leave sync metadata unchanged.

## Verifying Changes

You have access to multiple tools to verify your changes, both during and after development (executing snippets, looking at previews, getting build issues, running tests, etc.).
Prefer using these tools over manually calling `xcodebuild`.

### Building the Project

Use the Xcode MCP to build the project and check for errors:

```
tabId = mcp__xcode__XcodeListWindows() # Get tabIdentifier
mcp__xcode__BuildProject(tabIdentifier: tabId)
mcp__xcode__XcodeListNavigatorIssues(tabIdentifier: tabId) # or mcp__xcode__XcodeRefreshCodeIssuesInFile(tabIdentifier: tabId, filePath:) for a specific file
```

Ensure the app is in building order before finishing your work.

### Running Tests

Use `mcp__xcode__RunAllTests` to run all tests, or `mcp__xcode__RunSomeTests` to run specific tests.
Ensure all tests pass before finishing your work.

### Executing Snippets

If you need to test a specific snippet of code, use `mcp__xcode__ExecuteSnippet` to run it in the context of a specific file (with access to `fileprivate` declarations).

### Rendering Previews

You can render a SwiftUI preview to an image to quickly check how a view looks with `mcp__xcode__RenderPreview`.

### UI Automation (iOS)

For iOS, you can launch the app in a simulator and interact with it. Use this when replicating UI issues or after extensive updates.

1. Build and run the app: `mcp__xcodebuildmcp__build_run_sim()`
2. Take a screenshot: `mcp__xcodebuildmcp__screenshot()`
3. Get element coordinates: `mcp__xcodebuildmcp__describe_ui()`
4. Interact with UI: `tap`, `type_text`, `swipe`, etc.
5. Screenshot again to verify
6. **Always close the simulator when done**: `xcrun simctl shutdown <simulator-id>`
