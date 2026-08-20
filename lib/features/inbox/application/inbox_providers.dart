import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sidekick/core/domain/enums.dart';
import 'package:sidekick/core/providers/repository_providers.dart';
import 'package:sidekick/features/inbox/domain/capture.dart';

final StreamProvider<List<Capture>> inboxCapturesProvider =
    StreamProvider<List<Capture>>((Ref ref) {
      return ref
          .watch(capturesRepositoryProvider)
          .watchByStatuses(<CaptureStatus>{
            CaptureStatus.pending,
            CaptureStatus.processing,
            CaptureStatus.ready,
            CaptureStatus.failed,
          });
    });
