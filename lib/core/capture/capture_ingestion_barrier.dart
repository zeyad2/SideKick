import 'dart:async';

/// Coordinates local capture writes with the destructive sign-out database wipe.
class CaptureIngestionBarrier {
  bool _accepting = true;
  int _active = 0;
  Completer<void>? _drained;

  CaptureIngestionLease enter() {
    if (!_accepting) {
      throw StateError('Capture ingestion is paused for an auth transition.');
    }
    _active += 1;
    return CaptureIngestionLease._(this);
  }

  Future<void> closeAndDrain() async {
    _accepting = false;
    if (_active == 0) return;
    _drained ??= Completer<void>();
    await _drained!.future;
  }

  void reopen() {
    _accepting = true;
    _drained = null;
  }

  void _leave() {
    _active -= 1;
    final Completer<void>? drained = _drained;
    if (_active == 0 && drained != null) {
      if (!drained.isCompleted) drained.complete();
    }
  }
}

class CaptureIngestionLease {
  CaptureIngestionLease._(this._barrier);
  final CaptureIngestionBarrier _barrier;
  bool _closed = false;

  /// True when sign-out started while this lease was active.
  bool get invalidated => !_barrier._accepting;

  void close() {
    if (_closed) return;
    _closed = true;
    _barrier._leave();
  }
}
