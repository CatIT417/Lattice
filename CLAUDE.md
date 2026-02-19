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

### Core Design: Unified Block Table

Rather than separate tables, Lattice uses a **single `blocks` table** with views for type-safe access:

```
blocks (table)
├── pages (view) ─────── blocks WHERE title IS NOT NULL
└── paragraphs (view) ── blocks WHERE string IS NOT NULL
```

**Key constraint**: `(title IS NOT NULL) != (string IS NOT NULL)` - a block is either a page OR a paragraph, never both.

### Tables

**blocks** - The unified storage for all content (`src/Models/Block.swift`)
**blockReferences** - Links between blocks (`src/Models/Reference.swift`)
**blockAncestors** - Pre-computed ancestor relationships for O(1) tree queries (`src/Models/Ancestor.swift`)
**\_trigger_guard** - Temporary table for preventing cascading triggers (`src/Models/TriggerGuard.swift`)

### Views (Temporary, created on each connection)

- **pages** - Filters blocks with titles (`src/Models/Page.swift`)
- **paragraphs** - Filters blocks with strings (`src/Models/Paragraph.swift`)
- **backlinks** - Joins references with source block and page info (`src/Models/Backlink.swift`)

### Triggers

- **TouchTimestamps** - Auto-updates `updatedAt` on block modifications and parent page's `updatedAt` when a paragraph is modified
- **SyncAncestorsTable** - Automatically maintains ancestor table on block insert/update
- **Make{Pages/Paragraphs}ViewWritable** - INSTEAD OF triggers that redirect INSERT/DELETE on views to the blocks table (no UPDATE redirects for performance reasons, use `blocks` directly)
- **SyncReferencesTable** - Extracts references from block text and syncs to blockReferences table; auto-creates pages for newly mentioned `[[Page Links]]`; also updates blocks when a referenced page's title changes
- **UpdateParagraphOrder** - Maintains correct ordering of sibling blocks when inserting, moving, or deleting; uses `TriggerGuard` to prevent cascading trigger issues
- **AvoidDuplicatePages** - Prevents duplicate pages with the same title; when duplicates are detected (on INSERT or UPDATE), merges them by keeping the oldest page and moving all blocks to it

## Key Patterns

### Type-Safe Queries with SQLiteData

> Use the `pfw-structured-queries` skill when you need to write type-safe queries.

```swift
// Fetch children of a block
Paragraph.where { $0.parentId == blockId }.order(by: \.order)

// Fetch ancestors ordered root-first
Ancestor.where { $0.blockId == blockId }
    .order { $0.depth.desc() }
    .join(Block.all) { $0.ancestorId.eq($1.id) }
```

### @FetchAll / @FetchOne Property Wrappers

> Use the `pfw-sqlite-data` skill when you need help with data fetching

```swift
struct BlockView: View {
    @FetchOne var block: Block?
    @FetchAll var children: [Block]

    init(blockId: Block.ID) {
        _block = FetchOne(Block.find(blockId))
        _children = FetchAll(Block.where { $0.parentId == blockId }.order(by: \.order))
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

Each `TextRef` includes a `.url` property for deep linking and a `.resolved()` method for converting to block IDs.

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
    case block(id: UUID)  // Routes to page or paragraph based on block.kind, avoid if type is known
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

1. Configure SQLite (foreign keys, disable recursive triggers)
2. Create temporary views (in `prepareDatabase` callback)
3. Run migrations (blocks → references → ancestors → trigger guard)
4. Install triggers
5. Seed data (only on `LatticeDev` target)

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
