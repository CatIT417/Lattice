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
- **SQLiteData** - Type-safe GRDB wrapper with macros
- **NavigationKit** - Custom navigation library for routing
- **Dependencies** - Pointfree-style dependency injection

Use the library-docs skill if you need extra info on any of these, and the sosumi MCP for SwiftUI & other Apple docs.

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

**blocks** - The unified storage for all content

- `id: UUID` - Primary key
- `string: String?` - Text content (NULL for pages)
- `title: String?` - Page title (NULL for paragraphs)
- `parentId: Block.ID?` - Parent block (NULL for root pages)
- `pageId: Block.ID?` - Root page this block belongs to
- `order: Int` - Position among siblings
- `heading: HeadingLevel?` - H1, H2, H3
- `viewType: ViewType` - bullet, document, numbered
- `textAlign: TextAlignment` - left, center, right, justify
- `isOpen: Bool` - Collapsed state
- `props: String?` - JSON blob for extensibility
- `createdAt: Date` - Unix timestamp of creation
- `updatedAt: Date` - Unix timestamp of last modification

**blockReferences** - Links between blocks

- `sourceBlockId` - Block containing the reference
- `targetBlockId` - Block being referenced
- `kind` - tag, page_link, block_ref, block_embed

**blockAncestors** - Pre-computed ancestor relationships for O(1) tree queries

- `blockId` - The descendant
- `ancestorId` - An ancestor
- `depth` - 1 = parent, 2 = grandparent, etc.

### Views (Temporary, created on each connection)

- **pages** - Filters blocks with titles, projects to Page model
- **paragraphs** - Filters blocks with strings, projects to Paragraph model
- **backlinks** - Joins references with source block and page info

### Triggers

- **TouchTimestamps** - Auto-updates `updatedAt` on block modifications
- **SyncAncestorsTable** - Automatically maintains ancestor table on block insert/update
- **MakePagesViewWritable** / **MakeParagraphsViewWritable** - INSTEAD OF triggers that redirect INSERT/UPDATE/DELETE on views to the blocks table
- **SyncReferencesTable** - Extracts references from block text and syncs to blockReferences table; auto-creates pages for newly mentioned `[[Page Links]]`; also updates blocks when a referenced page's title changes (uses `@DatabaseFunction` for async processing)

## Key Patterns

### Type-Safe Queries with SQLiteData

```swift
// Fetch children of a block
Paragraph.where { $0.parentId == blockId }.order(by: \.order)

// Fetch ancestors ordered root-first
Ancestor.where { $0.blockId == blockId }
    .order { $0.depth.desc() }
    .join(Block.all) { $0.ancestorId.eq($1.id) }
```

### @FetchAll / @FetchOne Property Wrappers

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
Page.withChildren(id: pageId) // Returns `Page.WithChildren` (see `Table+withChildren.swift`)
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

## File Structure

```
src/
├── App.swift                      # Entry point, bootstraps database
├── Database/
│   ├── Database.swift            # DB setup: migrations, views, triggers, seeding
│   ├── Migration.swift           # Protocols for migrations/seeders/views/triggers
│   ├── Migrations/               # Schema migrations (numbered)
│   ├── Views/                    # SQL view definitions
│   └── Triggers/                 # SQL trigger definitions
├── Models/                       # @Table models (Block, Page, Paragraph, etc.)
├── ViewModels/                   # View models and coordinators
├── Extensions/                   # Swift extensions
├── Support/                      # Shared utilities (AttributedStringBuilder, BlockTree, etc.)
└── Views/
    ├── Pages/                    # Full-screen views (PageScreen, etc.)
    └── Components/               # Reusable UI components
        └── EditableText/         # Text editor (platform-specific files)
```

## Navigation

Uses NavigationKit with typed destinations:

```swift
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

### Platform Differences

| Aspect      | iOS/visionOS                                   | macOS                     |
| ----------- | ---------------------------------------------- | ------------------------- |
| Text view   | `UITextView` (wrapped in `AutosizingTextView`) | `NSTextView`              |
| Focus start | `textViewDidBeginEditing(_:)`                  | `textDidBeginEditing(_:)` |
| Link click  | `primaryActionFor textItem:`                   | `clickedOnLink:at:`       |
| Return key  | `shouldChangeTextIn:replacementText:`          | `doCommandBy:`            |

## Database Initialization Order

1. Configure SQLite (foreign keys, tracing)
2. Create temporary views (in `prepareDatabase` callback)
3. Run migrations (blocks → references → ancestors)
4. Install triggers
5. Seed data (DEBUG only)

## Verifying Changes

Use the xcodebuild MCP to build, run, and test the app in the iOS Simulator.

### Setup

First, set session defaults:

```
mcp__xcodebuildmcp__list_sims()
mcp__xcodebuildmcp__session-set-defaults(projectPath: "Lattice.xcodeproj", scheme: "Lattice", simulatorId: "...", useLatestOS: true)
```

### Build & Run

Build the app and launch it in the simulator: `mcp__xcodebuildmcp__build_run_sim()`
If you only need to build without running: `mcp__xcodebuildmcp__build_sim()`

### Visual Verification

**Take a screenshot** to see the current state: `mcp__xcodebuildmcp__screenshot()`

### UI Interaction

Use XCodeBuildMCP's UI interaction tools (`mcp__xcodebuildmcp__tap`, `mcp__xcodebuildmcp__type_text`, etc.)

### Testing Workflow

1. Build and run the app with `build_run_sim`
2. Take a screenshot to verify initial state
3. Use `describe_ui` to get element coordinates
4. Interact with the UI (tap, type, scroll)
5. Take another screenshot to verify the result
6. Repeat as needed to test different flows
7. **Always close the simulator when done**: `xcrun simctl shutdown <simulator-id>`
