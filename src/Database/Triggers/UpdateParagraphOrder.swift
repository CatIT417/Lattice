import SQLiteData

final class UpdateParagraphOrder: Trigger {
	static func install(in db: Database) throws {
		try Block.createTemporaryTrigger(after: .insert(forEachRow: { paragraph in
			TriggerGuard.increment()

			Block
				.where { $0.id != paragraph.id && $0.parentId == paragraph.parentId && $0.order >= paragraph.order }
				.update {
					$0.order += 1
				}

			TriggerGuard.decrement()
		}, when: { block in
			block.string.isNot(nil)
		})).execute(db)

		try Block.createTemporaryTrigger(after: .update(of: \.parentId, forEachRow: { old, new in
			TriggerGuard.increment()

			// Close gap in old parent
			Block
				.where { $0.parentId == old.parentId && $0.order > old.order }
				.update { $0.order -= 1 }

			// Make room in new parent
			Block
				.where { $0.id != new.id && $0.parentId == new.parentId && $0.order >= new.order }
				.update { $0.order += 1 }

			TriggerGuard.decrement()
		}, when: { old, new in
			new.string.isNot(nil) && old.parentId != new.parentId
		})).execute(db)

		try Block.createTemporaryTrigger(after: .update(of: \.order, forEachRow: { old, new in
			// Moving down: shift (old, new] down by 1
			Block
				.where {
					old.order < new.order
						&& $0.id != new.id
						&& $0.parentId == new.parentId
						&& $0.order > old.order
						&& $0.order <= new.order
				}
				.update { $0.order -= 1 }

			// Moving up: shift [new, old) up by 1
			Block
				.where {
					old.order > new.order
						&& $0.id != new.id
						&& $0.parentId == new.parentId
						&& $0.order >= new.order
						&& $0.order < old.order
				}
				.update { $0.order += 1 }
		}, when: { old, new in
			new.string.isNot(nil) && old.parentId == new.parentId && !TriggerGuard.isActive
		})).execute(db)

		try Block.createTemporaryTrigger(after: .delete(forEachRow: { paragraph in
			TriggerGuard.increment()

			Block
				.where { $0.parentId == paragraph.parentId && $0.order > paragraph.order }
				.update { $0.order -= 1 }

			TriggerGuard.decrement()
		}, when: { block in
			block.string.isNot(nil)
		})).execute(db)
	}
}
