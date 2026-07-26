import 'package:sidekick/features/inbox/domain/proposed_item.dart';

/// The §12.1 auto-commit eligibility gate (docs/CAPTURE_DECOMPOSITION.md).
///
/// A capture skips the review pass and materialises straight to real rows
/// **only when every condition holds**. The gate is deliberately STRUCTURAL and
/// computed client-side from the drafts — the model's `confidence` is an input
/// (condition 2) but cannot itself force an auto-commit. Rant length is not an
/// input: homogeneity + the count cap already cover the long-rambling case.
abstract final class AutoCommit {
  /// Max tasks that may be silently materialised (and later bulk-undone) from a
  /// single capture. More than a few is too much to have happened unseen.
  static const int maxItems = 3;

  static bool isEligible(List<ProposedItem> items) {
    // Empty never happens in practice (empty extraction becomes a single note
    // fallback, §11) — but a note is not a task, so it fails condition 1 anyway.
    if (items.isEmpty || items.length > maxItems) return false;
    for (final ProposedItem item in items) {
      // 1. every item is a task; 2. every item is high-confidence.
      if (!item.isTask || !item.isHighConfidence) return false;
    }
    return true;
  }
}
