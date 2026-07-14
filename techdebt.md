# Tech debt ledger

Known, consciously-accepted debt and forward-looking traps. Each entry names the
phase where it bites, so it surfaces before that phase starts rather than mid-work.

---

## TasksRepository has no stale-cutoff query (bites P9)

**What.** `TasksRepositoryImpl` (`lib/features/tasks/data/tasks_repository_impl.dart`)
exposes only `watchAll()` and `watchByStatus(status)`. Neither pushes a date
predicate into SQL, so there is no way to ask for "tasks untouched since
`:cutoff`" through the repository interface.

**Why it matters.** The schema ships an index built exactly for this —
`idx_tasks_stale` on `last_activity_at` — for P9's "stale task" surfacing. With
the current interface, P9 can only load *all* tasks and filter in Dart, which
never touches the index and degrades as the task count grows.

**The trap.** This is not a P2/P3 defect — nothing today is broken, and the
frozen repository interface was deliberately not widened speculatively. The risk
is discovering it mid-P9 and being surprised.

**Fix when P9 starts.** Add a query method that pushes the cutoff down, e.g.
`Stream<List<Task>> watchStale({required DateTime before})` selecting
`WHERE last_activity_at < :before AND deleted_at IS NULL`, so the index is used.
Or make a *conscious* decision to accept in-memory filtering for the expected
task volume — but decide it explicitly, don't back into it.
