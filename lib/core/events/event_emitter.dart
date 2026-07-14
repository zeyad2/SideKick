import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sidekick/core/data/id_generator.dart';
import 'package:sidekick/core/events/domain_event.dart';
import 'package:sidekick/core/events/events_repository.dart';

/// The event-emission hook the repositories ride on (D9).
///
/// CONTRACT: emission is a fire-and-forget SIDE EFFECT that can NEVER block or
/// fail the user mutation it rides on. Every method returns `void` synchronously
/// and swallows all errors — a failed event write is invisible to the caller.
/// Repositories call this; they never `await` it.
class EventEmitter {
  EventEmitter(this._repo, this._idGenerator, {DateTime Function()? clock})
    : _clock = clock ?? (() => DateTime.now().toUtc());

  final EventsRepository _repo;
  final IdGenerator _idGenerator;
  final DateTime Function() _clock;

  final Set<Future<void>> _inFlight = <Future<void>>{};

  /// Emit an arbitrary domain event. Non-blocking; errors are swallowed.
  void emit({
    required String userId,
    required String eventType,
    String? entityType,
    String? entityId,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    final DomainEvent event = DomainEvent(
      id: _idGenerator.v4(),
      userId: userId,
      eventType: eventType,
      entityType: entityType,
      entityId: entityId,
      metadata: metadata,
      occurredAt: _clock(),
    );
    _track(_safeAppend(event));
  }

  /// Structural `<entity>_created` event (P2 generic layer owns this).
  void emitCreated({
    required String userId,
    required String entityType,
    required String entityId,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) => emit(
    userId: userId,
    eventType: StructuralEventSuffix.createdFor(entityType),
    entityType: entityType,
    entityId: entityId,
    metadata: metadata,
  );

  /// Structural `<entity>_status_changed` event with `{from, to}`.
  void emitStatusChanged({
    required String userId,
    required String entityType,
    required String entityId,
    required String from,
    required String to,
  }) => emit(
    userId: userId,
    eventType: StructuralEventSuffix.statusChangedFor(entityType),
    entityType: entityType,
    entityId: entityId,
    metadata: <String, Object?>{'from': from, 'to': to},
  );

  Future<void> _safeAppend(DomainEvent event) async {
    try {
      await _repo.append(event);
    } catch (error, stackTrace) {
      // Best-effort: an event write must never surface to the user mutation.
      if (kDebugMode) {
        debugPrint('EventEmitter: dropped event ${event.eventType}: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }
  }

  void _track(Future<void> future) {
    _inFlight.add(future);
    future.whenComplete(() => _inFlight.remove(future));
  }

  /// TEST-ONLY: await all in-flight emissions so assertions are deterministic.
  @visibleForTesting
  Future<void> settle() async {
    while (_inFlight.isNotEmpty) {
      await Future.wait(_inFlight.toList());
    }
  }
}
