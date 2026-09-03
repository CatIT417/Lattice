import Foundation
import SQLiteData

final class SyncReferencesTable: Trigger {
	static var uses: [any ScalarDatabaseFunction] {
		[$syncReferencesFromText, $reextractReferencesMentioningTitle, $reextractReferencesMentioningBlock, $updatePageTitleInReferences, $cleanReferencesForDeletedPage]
	}

	static func install(in db: Database) throws {
		try Block.createTemporaryTrigger(after: .insert(forEachRow: { block in
			Select($syncReferencesFromText(new: block.string.unsafelyUnwrapped, forBlockID: block.id))
		}, when: { block in
			block.string.isNot(nil)
		}))
		.execute(db)

		try Block.createTemporaryTrigger(after: .update(of: \.string, forEachRow: { _, block in
			Select($syncReferencesFromText(new: block.string.unsafelyUnwrapped, forBlockID: block.id))
		}, when: { old, new in
			new.string.isNot(nil) && old.string.neq(new.string)
		}))
		.execute(db)

		// Handles edits performed remotely that might have lost their references

		try Block.createTemporaryTrigger(after: .insert(forEachRow: { block in
			Select($reextractReferencesMentioningTitle(block.title.unsafelyUnwrapped))
		}, when: { block in
			block.title.isNot(nil)
		}))
		.execute(db)

		try Block.createTemporaryTrigger(after: .insert(forEachRow: { block in
			Select($reextractReferencesMentioningBlock(block.id))
		}, when: { block in
			block.string.isNot(nil)
		}))
		.execute(db)

		// When renaming remotely, paragraphs might arrive before the page title update.
		// If so, they got unsynced, and we pick them back up here.
		try Block.createTemporaryTrigger(after: .update(of: \.title, forEachRow: { _, new in
			Select($reextractReferencesMentioningTitle(new.title.unsafelyUnwrapped))
		}, when: { old, new in
			new.title.isNot(nil) && old.title.neq(new.title)
		}))
		.execute(db)

		// Edit blocks referencing a page whose title changed. Only happens locally, as the origin will propagate its own changes.
		try Block.createTemporaryTrigger(after: .update(of: \.title, forEachRow: { old, new in
			Select($updatePageTitleInReferences(old: old.title.unsafelyUnwrapped, new: new.title.unsafelyUnwrapped, forPageID: new.id))
		}, when: { old, new in
			!SyncEngine.$isSynchronizing && new.title.isNot(nil) && old.title.neq(new.title) && Reference.where { $0.targetBlockId.eq(new.id) }.exists()
		}))
		.execute(db)

		try Block.createTemporaryTrigger(before: .delete(forEachRow: { block in
			Select($cleanReferencesForDeletedPage(title: block.title.unsafelyUnwrapped, forPageID: block.id))
		}, when: { block in
			!SyncEngine.$isSynchronizing && block.title.isNot(nil) && Reference.where { $0.targetBlockId.eq(block.id) }.exists()
		}))
		.execute(db)
	}
}

fileprivate enum ReferenceSync {
	/// Blocks whose references are being recomputed further up the current call stack.
	///
	/// Creating a page while resolving a block's links fires the page's insert trigger, whose re-extraction would otherwise re-process the very block still being resolved.
	@TaskLocal static var blocksBeingSynced: Set<Block.ID> = []
}

/// Recomputes the reference rows for a block from its text.
///
/// Pages mentioned by `[[link]]`/`#tag` are only created when `createMissingPages` is set, which callers do for local edits only.
/// While the sync engine is applying remote rows the page may simply not have arrived yet, and creating it here would produce a local-only duplicate.
/// Such references, and `((refs))` to blocks that do not exist yet, are skipped and picked up by the re-extraction triggers once their target arrives.
func syncReferences(for blockID: Block.ID, text: String, createMissingPages: Bool, in db: Database) throws {
	@Dependency(\.uuid) var uuid

	try ReferenceSync.$blocksBeingSynced.withValue(ReferenceSync.blocksBeingSynced.union([blockID])) {
		let references = try text.extractRefs().compactMap { try $0.resolved(using: db, createMissingPages: createMissingPages) }

		try Reference.where { $0.sourceBlockId.eq(blockID) }.delete().execute(db)
		guard !references.isEmpty else { return }

		try Reference.insert {
			for reference in references {
				Reference(id: uuid(), sourceBlockId: blockID, targetBlockId: reference.targetID, kind: reference.kind)
			}
		}
		.execute(db)
	}
}

@DatabaseFunction
func syncReferencesFromText(new: String, forBlockID blockID: Paragraph.ID) {
	@Dependency(\.defaultDatabase) var database

	withErrorReporting {
		try database.unsafeReentrantWrite { db in
			try syncReferences(for: blockID, text: new, createMissingPages: !SyncEngine.isSynchronizing, in: db)
		}
	}
}

@DatabaseFunction
func reextractReferencesMentioningTitle(_ title: String) {
	let day = DayOfYear(title: title)

	reextractReferences(matching: title, targets: Page.where { $0.title.eq(title) }.select(\.id)) { ref in
		guard ref.kind.isPage else { return false }
		if ref.target == title { return true }
		if let day, DayOfYear(title: ref.target) == day { return true }
		return false
	}
}

@DatabaseFunction
func reextractReferencesMentioningBlock(_ id: Block.ID) {
	reextractReferences(matching: id.uuidString, targets: Block.find(id).select(\.id)) { ref in
		ref.kind.isBlock && UUID(uuidString: ref.target) == id
	}
}

/// Re-runs reference extraction for paragraphs whose text contains `needle` and references the block it stands for.
///
/// This only rebuilds derived rows: a paragraph that arrived from the sync engine may mention other pages that have
/// not arrived yet, and creating those here (even from a local write) would duplicate the remote page.
fileprivate func reextractReferences(matching needle: String, targets: some Statement<Block.ID>, where isMatch: (TextRef) -> Bool) {
	@Dependency(\.defaultDatabase) var database

	// A phrase query only: unlike `String.quoted()` (built for search), this must not match paragraphs that merely share a word with the title
	let phrase = "\"\(needle.replacingOccurrences(of: "\"", with: "\"\""))\""

	withErrorReporting {
		try database.unsafeReentrantWrite { db in
			let candidates = try Paragraph
				.join(BlockText.all) { $0.id.eq($1.blockID) }
				.where { paragraphs, texts in
					texts.match(phrase)
						&& !Reference.where { $0.sourceBlockId.eq(paragraphs.id) && $0.targetBlockId.in(targets) }.exists()
				}
				.select { paragraphs, _ in paragraphs }
				.fetchAll(db)

			for paragraph in candidates where !ReferenceSync.blocksBeingSynced.contains(paragraph.id) {
				guard paragraph.string.extractRefs().contains(where: isMatch) else { continue }
				try syncReferences(for: paragraph.id, text: paragraph.string, createMissingPages: false, in: db)
			}
		}
	}
}

@DatabaseFunction
func cleanReferencesForDeletedPage(title: String, forPageID pageID: Page.ID) {
	@Dependency(\.defaultDatabase) var database

	withErrorReporting {
		try database.unsafeReentrantWrite { db in
			let blocks = try Reference
				.group(by: \.sourceBlockId)
				.where { $0.targetBlockId.eq(pageID) }
				.join(Paragraph.all) { $0.sourceBlockId.eq($1.id) }
				.select { $1 }
				.fetchAll(db)

			let spaceChar: unichar = 0x20

			for block in blocks {
				let original = block.string
				let references = original.extractRefs().filter { $0.kind.isPage && $0.target == title }
				guard !references.isEmpty else { continue }

				let mutable = NSMutableString(string: original)
				let ranges = references.map { ref in
					(ref: ref, range: NSRange(ref.range, in: original))
				}
				.sorted { $0.range.location > $1.range.location }

				for item in ranges {
					switch item.ref.kind {
						case .pageLink: mutable.replaceCharacters(in: item.range, with: item.ref.target)
						case .tag:
							var range = item.range
							if range.location > 0, mutable.character(at: range.location - 1) == spaceChar {
								range = NSRange(location: range.location - 1, length: range.length + 1)
							} else if NSMaxRange(range) < mutable.length, mutable.character(at: NSMaxRange(range)) == spaceChar {
								range = NSRange(location: range.location, length: range.length + 1)
							}
							mutable.replaceCharacters(in: range, with: "")
						default:
							break
					}
				}

				let updated = mutable as String
				guard updated != original else { continue }

				try Block.find(block.id)
					.update {
						$0.string = #bind(updated)
					}
					.execute(db)
			}
		}
	}
}

@DatabaseFunction
func updatePageTitleInReferences(old: String, new: String, forPageID pageID: Page.ID) {
	@Dependency(\.defaultDatabase) var database

	withErrorReporting {
		try database.unsafeReentrantWrite { db in
			let blocks = try Reference
				.group(by: \.sourceBlockId)
				.where { $0.targetBlockId.eq(pageID) }
				.join(Paragraph.all) { $0.sourceBlockId.eq($1.id) }
				.select { $1 }
				.fetchAll(db)

			for block in blocks {
				let original = block.string
				let references = original.extractRefs().filter { $0.kind.isPage && $0.target == old }
				guard !references.isEmpty else { continue }

				let mutable = NSMutableString(string: original)
				let ranges = references
					.map { ref in
						(ref: ref, range: NSRange(ref.range, in: original))
					}
					.sorted { $0.range.location > $1.range.location }

				for item in ranges {
					guard let replacement = item.ref.replacement(forRenamedPage: new) else { continue }
					mutable.replaceCharacters(in: item.range, with: replacement)
				}

				let updated = mutable as String
				guard updated != original else { continue }

				try Block.find(block.id)
					.update {
						$0.string = #bind(updated)
					}
					.execute(db)
			}
		}
	}
}
