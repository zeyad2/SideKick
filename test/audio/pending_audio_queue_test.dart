import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sidekick/core/audio/pending_audio_queue.dart';

void main() {
  late Directory tempDir;
  late DirectoryPendingAudioQueue queue;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('sidekick_audio_test');
    queue = DirectoryPendingAudioQueue(baseDir: tempDir);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('enqueued audio is listed, then removable', () async {
    final PendingAudio entry = await queue.enqueueBytes(<int>[1, 2, 3]);
    expect(entry.file.existsSync(), isTrue);

    final List<PendingAudio> pending = await queue.pending();
    expect(pending.map((PendingAudio e) => e.id), contains(entry.id));

    await queue.remove(entry.id);
    expect(await queue.pending(), isEmpty);
  });

  test('reservePath returns a writable path under pending_audio/', () async {
    final File path = await queue.reservePath();
    expect(path.path.replaceAll(r'\', '/'), contains('/pending_audio/'));
    // Reserve does not create the file; the recorder does.
    expect(path.existsSync(), isFalse);

    await path.writeAsBytes(<int>[9]);
    final List<PendingAudio> pending = await queue.pending();
    expect(pending.length, 1);
  });
}
