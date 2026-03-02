import SQLiteData

final class UpdateParagraphOrder: Trigger {
	static func install(in db: Database) throws {
		try Block.createTemporaryTrigger(after: .insert(forEachRow: { paragraph in
			TriggerGuard.increment()

			// First, we increment the order of all sibling paragraphs that come after the inserted one
			Block
				.where { $0.id.neq(paragraph.id) && $0.parentId.eq(paragraph.parentId) && $0.order >= paragraph.order }
				.update { $0.order += 1 }

			// Then, we clamp the inserted paragraph's order to not exceed the max if needed
			Self.clampToMaxOrder(for: paragraph)

			TriggerGuard.decrement()
		}, when: { block in
			block.string.isNot(nil)
		})).execute(db)

		try Block.createTemporaryTrigger(after: .update(of: \.parentId, forEachRow: { old, new in
			TriggerGuard.increment()

			// Close gap in old parent
			Block
				.where { $0.parentId.eq(old.parentId) && $0.order > old.order }
				.update { $0.order -= 1 }

			// Make room in new parent
			Block
				.where { $0.id.neq(new.id) && $0.parentId.eq(new.parentId) && $0.order >= new.order }
				.update { $0.order += 1 }

			// Clamp to max order in new parent
			Self.clampToMaxOrder(for: new)

			TriggerGuard.decrement()
		}, when: { old, new in
			new.string.isNot(nil) && old.parentId.neq(new.parentId)
		})).execute(db)

		try Block.createTemporaryTrigger(after: .update(of: \.order, forEachRow: { old, new in
			// Moving down: shift (old, new] down by 1
			Block
				.where {
					old.order < new.order
						&& $0.id.neq(new.id)
						&& $0.parentId.eq(new.parentId)
						&& $0.order > old.order
						&& $0.order <= new.order
				}
				.update { $0.order -= 1 }

			// Moving up: shift [new, old) up by 1
			Block
				.where {
					old.order > new.order
						&& $0.id.neq(new.id)
						&& $0.parentId.eq(new.parentId)
						&& $0.order >= new.order
						&& $0.order < old.order
				}
				.update { $0.order += 1 }

			// Clamp to max order in parent
			Self.clampToMaxOrder(for: new)
		}, when: { old, new in
			new.string.isNot(nil) && old.parentId.eq(new.parentId) && !TriggerGuard.isActive
		})).execute(db)

		try Block.createTemporaryTrigger(after: .delete(forEachRow: { paragraph in
			TriggerGuard.increment()

			Block
				.where { $0.parentId.eq(paragraph.parentId) && $0.order > paragraph.order }
				.update { $0.order -= 1 }

			TriggerGuard.decrement()
		}, when: { block in
			block.string.isNot(nil)
		})).execute(db)
	}

	@QueryFragmentBuilder<any Statement> private static func clampToMaxOrder<AliasName>(for paragraph: TableAlias<Block, AliasName>.TableColumns) -> [QueryFragment] {
		// Then, we fetch the max possible order for this parent
		let maxOrder = Block
			.where { $0.id.neq(paragraph.id) && $0.parentId.eq(paragraph.parentId) }
			.select { $0.order.max().ifnull(0) + 1 }

		// Finally, we clamp the inserted paragraph's order to not exceed the max if needed
		Block
			.where { $0.id.eq(paragraph.id) && $0.order > maxOrder }
			.where { _ in !SyncEngine.$isSynchronizing }
			.update { $0.order = maxOrder }
	}
}
