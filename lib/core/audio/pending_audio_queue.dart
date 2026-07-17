import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// A single queued audio file awaiting transcription.
@immutable
class PendingAudio {
  const PendingAudio({
    required this.id,
    required this.file,
    required this.enqueuedAt,
  });

  /// Stable id == the file's base name.
  final String id;
  final File file;
  final DateTime enqueuedAt;
}

/// Device-storage queue for captured audio (the "capture must never be lost"
/// contract). The native capture pipeline (P3) writes audio to disk BEFORE any
/// network work and enqueues it here; transcription (P4) drains it.
///
/// This P2 deliverable provides the interface + a concrete directory-strategy
/// implementation; P3/P4 fill it with real audio and draining logic.
abstract interface class PendingAudioQueue {
  /// Reserve a destination path inside the queue directory for a recorder to
  /// write to directly (so the bytes hit disk before anything else). The file
  /// is not created here — the caller writes it, then it counts as pending.
  Future<File> reservePath({String extension = 'm4a'});

  /// Write [bytes] to a new queue file and return the entry.
  Future<PendingAudio> enqueueBytes(
    List<int> bytes, {
    String extension = 'm4a',
  });

  /// All queued audio files, oldest first.
  Future<List<PendingAudio>> pending();

  /// Remove a drained entry by [id].
  Future<void> remove(String id);
}

/// Stores each pending audio as a file under `<baseDir>/pending_audio/`.
/// [baseDir] is injected so tests can point at a temp directory (the app wires
/// it to the platform documents directory).
class DirectoryPendingAudioQueue implements PendingAudioQueue {
  DirectoryPendingAudioQueue({
    required Directory baseDir,
    String Function()? idFactory,
  }) : _dir = Directory(p.join(baseDir.path, 'pending_audio')),
       _idFactory =
           idFactory ??
           (() => DateTime.now().toUtc().microsecondsSinceEpoch.toString());

  final Directory _dir;
  final String Function() _idFactory;

  Future<Directory> _ensureDir() async {
    if (!_dir.existsSync()) {
      await _dir.create(recursive: true);
    }
    return _dir;
  }

  @override
  Future<File> reservePath({String extension = 'm4a'}) async {
    await _ensureDir();
    return File(p.join(_dir.path, '${_idFactory()}.$extension'));
  }

  @override
  Future<PendingAudio> enqueueBytes(
    List<int> bytes, {
    String extension = 'm4a',
  }) async {
    final File file = await reservePath(extension: extension);
    await file.writeAsBytes(bytes, flush: true);
    return PendingAudio(
      id: p.basename(file.path),
      file: file,
      enqueuedAt: file.statSync().modified,
    );
  }

  @override
  Future<List<PendingAudio>> pending() async {
    await _ensureDir();
    final List<PendingAudio> entries =
        _dir
            .listSync()
            .whereType<File>()
            .map(
              (File f) => PendingAudio(
                id: p.basename(f.path),
                file: f,
                enqueuedAt: f.statSync().modified,
              ),
            )
            .toList(growable: true)
          ..sort(
            (PendingAudio a, PendingAudio b) =>
                a.enqueuedAt.compareTo(b.enqueuedAt),
          );
    return entries;
  }

  @override
  Future<void> remove(String id) async {
    final File file = File(p.join(_dir.path, id));
    if (file.existsSync()) {
      await file.delete();
    }
  }
}
