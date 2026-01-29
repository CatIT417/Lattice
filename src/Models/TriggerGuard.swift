import SQLiteData

@Table("_trigger_guard")
struct TriggerGuard {
	let id: Int
	var depth: Int

	init(depth: Int = 0) {
		id = 0
		self.depth = depth
	}

	static var isActive: Select<Bool, TriggerGuard, Void> {
		TriggerGuard
			.where { $0.id == 0 }
			.select { $0.depth.gt(0) }
			.asSelect()
	}

	static func increment() -> UpdateOf<TriggerGuard> {
		TriggerGuard.find(0)
			.update { $0.depth += 1 }
	}

	static func decrement() -> UpdateOf<TriggerGuard> {
		TriggerGuard.find(0)
			.update { $0.depth -= 1 }
	}
}
