import 'package:flutter_test/flutter_test.dart';
import 'package:sidekick/core/domain/enums.dart';
import 'package:sidekick/features/inbox/application/recent_auto_commits.dart';
import 'package:sidekick/features/inbox/domain/auto_commit_receipt.dart';
import 'package:sidekick/features/inbox/domain/capture.dart';
import 'package:sidekick/features/inbox/domain/proposed_item.dart';

void main() {
  Capture capture(String id, DateTime? committedAt) {
    final DateTime now = DateTime.utc(2026, 7, 18);
    return Capture(
      id: id,
      userId: 'u1',
      llmType: LlmType.uncategorized,
      status: committedAt == null ? CaptureStatus.ready : CaptureStatus.triaged,
      capturedAt: now,
      createdAt: now,
      updatedAt: now,
      autoCommittedAt: committedAt,
      proposedItems: <ProposedItem>[
        ProposedItem(
          id: '$id-task',
          kind: ResultingType.task,
          title: id,
          confidence: DraftConfidence.high,
        ),
      ],
    );
  }

  test('durable projection restores auto-commits newest first', () {
    final List<AutoCommitReceipt> receipts = projectRecentAutoCommits(<Capture>[
      capture('older', DateTime.utc(2026, 7, 18, 10)),
      capture('ready', null),
      capture('newer', DateTime.utc(2026, 7, 18, 11)),
    ]);
    expect(
      receipts.map((AutoCommitReceipt receipt) => receipt.captureId),
      <String>['newer', 'older'],
    );
  });
}
