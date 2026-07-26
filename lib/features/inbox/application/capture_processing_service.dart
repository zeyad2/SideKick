import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sidekick/core/capture/capture_contract.dart';
import 'package:sidekick/core/capture/capture_ingestion_barrier.dart';
import 'package:sidekick/core/data/id_generator.dart';
import 'package:sidekick/core/domain/enums.dart';
import 'package:sidekick/core/sync/connectivity_service.dart';
import 'package:sidekick/features/inbox/application/capture_triage_service.dart';
import 'package:sidekick/features/inbox/data/gemini_client.dart';
import 'package:sidekick/features/inbox/domain/auto_commit.dart';
import 'package:sidekick/features/inbox/domain/capture.dart';
import 'package:sidekick/features/inbox/domain/capture_analysis.dart';
import 'package:sidekick/features/inbox/domain/proposed_item.dart';

/// Durable P4 worker. A failed API call changes only the row status; native
/// journal ownership and the audio file remain intact for the next retry.
class CaptureProcessingService {
  CaptureProcessingService({
    required this.captures,
    required this.gemini,
    required this.connectivity,
    required this.barrier,
    required this.triage,
    required this.idGenerator,
    this.onAutoCommit,
    this.baseRetryDelay = const Duration(seconds: 30),
  });

  final CapturesRepository captures;
  final GeminiClient gemini;
  final ConnectivityService connectivity;
  final CaptureIngestionBarrier barrier;

  /// Materialises drafts for the auto-commit path (§12.4), reusing the exact
  /// "Save all" path so auto-committed rows are indistinguishable from reviewed
  /// ones.
  final CaptureTriageService triage;

  /// Stamps each draft with its stable client id (§11) when `proposed_items` is
  /// written — Gemini is not trusted to supply one.
  final IdGenerator idGenerator;

  /// Notified after a capture is auto-committed WITHOUT review (§12.5), so the
  /// inbox "auto-added recently" strip can offer Undo/Edit. Fired only on the
  /// auto path, never on manual "Save all".
  final void Function(String captureId, List<ProposedItem> items)? onAutoCommit;
  final Duration baseRetryDelay;

  /// Max transcript characters kept as the fallback note's title (§11 empty
  /// extraction); the full transcript goes in the body.
  static const int _fallbackTitleMax = 80;

  final Set<String> _inFlight = <String>{};
  final Map<String, int> _attempts = <String, int>{};
  StreamSubscription<CapturedAudioEvent>? _captureSubscription;
  StreamSubscription<bool>? _connectivitySubscription;
  Timer? _retryTimer;
  bool _disposed = false;

  Future<void> start(Stream<CapturedAudioEvent> captureEvents) async {
    _captureSubscription = captureEvents.listen(
      (CapturedAudioEvent event) => unawaited(processById(event.captureRowId)),
    );
    _connectivitySubscription = connectivity.onConnectedChanged.listen((
      bool connected,
    ) {
      if (connected) unawaited(retryNow());
    });
    await retryNow();
  }

  Future<void> retryNow() async {
    if (_disposed) return;
    _retryTimer?.cancel();
    final List<Capture> queued = await captures.watchByStatuses(<CaptureStatus>{
      CaptureStatus.pending,
      CaptureStatus.processing,
      CaptureStatus.failed,
      CaptureStatus.ready,
    }).first;
    for (final Capture capture in queued.reversed) {
      await processById(capture.id);
    }
  }

  Future<void> processById(String captureId) async {
    if (_disposed || !_inFlight.add(captureId)) return;
    CaptureIngestionLease? lease;
    try {
      try {
        lease = barrier.enter();
      } on StateError {
        return;
      }
      final List<Capture> rows = await captures.getByIds(<String>[captureId]);
      if (rows.isEmpty) return;
      Capture capture = rows.single;
      if (capture.status == CaptureStatus.ready) {
        final List<ProposedItem> drafts =
            capture.proposedItems ?? const <ProposedItem>[];
        if (capture.autoCommittedAt == null &&
            capture.dispositionedItemIds.isEmpty &&
            AutoCommit.isEligible(drafts)) {
          await triage.saveAll(captureId, drafts, autoCommitted: true);
          onAutoCommit?.call(captureId, drafts);
        }
        return;
      }
      if (capture.status == CaptureStatus.triaged ||
          capture.status == CaptureStatus.discarded) {
        return;
      }
      final CapturesRepository repository = captures;
      if (repository is! CaptureProcessingTransitions) {
        throw StateError(
          'Captures repository does not support atomic processing transitions.',
        );
      }
      final CaptureProcessingTransitions transitions =
          repository as CaptureProcessingTransitions;
      final Capture? claimed = await transitions.beginProcessing(captureId);
      if (claimed == null) return;
      capture = claimed;
      final String? audioPath = capture.audioPath;
      if (audioPath == null || !File(audioPath).existsSync()) {
        debugPrint(
          'CaptureProcessing: capture $captureId has no audio file '
          '(path=$audioPath) — marking failed.',
        );
        final bool failed = await transitions.finishProcessing(
          capture.copyWith(status: CaptureStatus.failed),
        );
        if (failed) _scheduleRetry(captureId);
        return;
      }
      debugPrint(
        'CaptureProcessing: analyzing capture $captureId '
        '(${File(audioPath).lengthSync()} bytes) via Gemini…',
      );
      final CaptureAnalysis analysis = await gemini.analyzeCaptureAudio(
        File(audioPath),
      );
      debugPrint(
        'CaptureProcessing: capture $captureId analyzed — '
        '${analysis.items.length} item(s) extracted.',
      );
      final List<ProposedItem> drafts = _prepareDrafts(analysis);
      // `proposed_items` is written FIRST and retained — it is the durable audit
      // trail Undo/Edit and manual review read from (§12.4). The capture becomes
      // `ready` as the checkpoint; an eligible capture then advances to
      // `triaged` via the shared bulk path below. A crash after this point
      // leaves a reviewable `ready` capture — nothing the user said is lost.
      final bool completed = await transitions.finishProcessing(
        capture.copyWith(
          rawTranscript: analysis.rawTranscript,
          proposedItems: drafts,
          status: CaptureStatus.ready,
        ),
      );
      if (!completed) return;
      _attempts.remove(captureId);
      if (AutoCommit.isEligible(drafts)) {
        await triage.saveAll(captureId, drafts, autoCommitted: true);
        onAutoCommit?.call(captureId, drafts);
      }
    } catch (error, stackTrace) {
      debugPrint('CaptureProcessing: capture $captureId FAILED: $error');
      debugPrint('CaptureProcessing stack: $stackTrace');
      final List<Capture> rows = await captures.getByIds(<String>[captureId]);
      bool failed = false;
      if (rows.isNotEmpty && rows.single.status == CaptureStatus.processing) {
        final CapturesRepository repository = captures;
        if (repository is CaptureProcessingTransitions) {
          failed = await (repository as CaptureProcessingTransitions)
              .finishProcessing(
                rows.single.copyWith(status: CaptureStatus.failed),
              );
        }
      }
      if (rows.isNotEmpty &&
          rows.single.status == CaptureStatus.ready &&
          rows.single.dispositionedItemIds.isEmpty &&
          AutoCommit.isEligible(
            rows.single.proposedItems ?? const <ProposedItem>[],
          )) {
        failed = true;
      }
      if (failed) _scheduleRetry(captureId);
    } finally {
      lease?.close();
      _inFlight.remove(captureId);
    }
  }

  /// Stamps stable client ids onto the extracted drafts, applying the §11
  /// empty-extraction fallback: zero items → a single `note` carrying the raw
  /// transcript, so nothing the user said is silently lost.
  List<ProposedItem> _prepareDrafts(CaptureAnalysis analysis) {
    if (analysis.items.isEmpty) {
      final String transcript = analysis.rawTranscript.trim();
      final String title = transcript.length > _fallbackTitleMax
          ? '${transcript.substring(0, _fallbackTitleMax).trimRight()}…'
          : transcript;
      return <ProposedItem>[
        ProposedItem(
          id: idGenerator.v4(),
          kind: ResultingType.note,
          title: title.isEmpty ? 'Captured note' : title,
          confidence: DraftConfidence.low,
          details: transcript.isEmpty ? null : transcript,
        ),
      ];
    }
    return analysis.items
        .map((ProposedItem item) => item.withId(idGenerator.v4()))
        .toList(growable: false);
  }

  void _scheduleRetry(String captureId) {
    if (_disposed) return;
    final int attempt = (_attempts[captureId] ?? 0) + 1;
    _attempts[captureId] = attempt;
    final int multiplier = 1 << (attempt - 1).clamp(0, 5);
    final Duration delay = baseRetryDelay * multiplier;
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () => unawaited(retryNow()));
  }

  Future<void> dispose() async {
    _disposed = true;
    _retryTimer?.cancel();
    await _captureSubscription?.cancel();
    await _connectivitySubscription?.cancel();
    while (_inFlight.isNotEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }
}
