import 'package:meta/meta.dart';
import 'package:sidekick/features/inbox/domain/proposed_item.dart';

/// A record that a capture was auto-committed (docs/CAPTURE_DECOMPOSITION.md
/// §12.4) WITHOUT the user reviewing it — the material the §12.5 safety net
/// surfaces so the user can Undo or Edit right after the fact.
///
/// This is projected from durable capture state; the events log remains
/// write-only and is not used as a product read surface.
@immutable
class AutoCommitReceipt {
  const AutoCommitReceipt({
    required this.captureId,
    required this.items,
    required this.addedAt,
  });

  final String captureId;

  /// The drafts that were materialised — carries each item's kind and title so
  /// the strip can show what was added without a re-query.
  final List<ProposedItem> items;
  final DateTime addedAt;

  int get count => items.length;
}
