import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sidekick/core/domain/enums.dart';
import 'package:sidekick/core/providers/repository_providers.dart';
import 'package:sidekick/features/inbox/domain/auto_commit_receipt.dart';
import 'package:sidekick/features/inbox/domain/capture.dart';

/// Durable recent auto-commit projection. The source of truth is the capture's
/// persisted [Capture.autoCommittedAt], so the safety strip survives restarts.
final StreamProvider<List<AutoCommitReceipt>> recentAutoCommitsProvider =
    StreamProvider<List<AutoCommitReceipt>>((Ref ref) {
      return ref.watch(capturesRepositoryProvider).watchAll().map((rows) {
        return projectRecentAutoCommits(rows);
      });
    });

List<AutoCommitReceipt> projectRecentAutoCommits(List<Capture> rows) {
  final List<AutoCommitReceipt> receipts = <AutoCommitReceipt>[
    for (final Capture capture in rows)
      if (capture.status == CaptureStatus.triaged &&
          capture.autoCommittedAt != null &&
          capture.proposedItems != null)
        AutoCommitReceipt(
          captureId: capture.id,
          items: capture.proposedItems!,
          addedAt: capture.autoCommittedAt!,
        ),
  ];
  receipts.sort((a, b) => b.addedAt.compareTo(a.addedAt));
  return receipts;
}
