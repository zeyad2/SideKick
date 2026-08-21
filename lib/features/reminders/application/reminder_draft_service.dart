import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:sidekick/core/domain/enums.dart';

@immutable
class ReminderDraftContext {
  const ReminderDraftContext({required this.now, this.audioRetryCount = 0});

  final DateTime now;
  final int audioRetryCount;
}

@immutable
class ReminderDraftParseResult {
  const ReminderDraftParseResult({
    required this.drafts,
    this.rawTranscript,
    this.isUnclear = false,
  });

  final List<ParsedReminderDraft> drafts;
  final String? rawTranscript;
  final bool isUnclear;
}

@immutable
class ParsedReminderDraft {
  const ParsedReminderDraft({
    required this.title,
    required this.confidence,
    required this.triggerType,
    required this.explanation,
    this.details,
    this.scheduledAt,
    this.placeId,
    this.placeCandidate,
    this.geofenceTransition,
    this.dwellSeconds,
  });

  final String title;
  final String? details;
  final double confidence;
  final TaskReminderTriggerType triggerType;
  final DateTime? scheduledAt;
  final String? placeId;
  final String? placeCandidate;
  final GeofenceTransition? geofenceTransition;
  final int? dwellSeconds;
  final String explanation;

  bool get hasConcreteTrigger => switch (triggerType) {
    TaskReminderTriggerType.time => scheduledAt != null,
    TaskReminderTriggerType.place => placeId != null,
  };
}

abstract interface class ReminderDraftService {
  Future<ReminderDraftParseResult> parseText(
    String input,
    ReminderDraftContext context,
  );

  Future<ReminderDraftParseResult> parseAudio(
    File file,
    ReminderDraftContext context,
  );
}

class ReminderDraftFormatException implements Exception {
  const ReminderDraftFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

class HeuristicReminderDraftService implements ReminderDraftService {
  const HeuristicReminderDraftService();

  static const Set<String> _blockedKinds = <String>{
    'habit',
    'habits',
    'goal',
    'goals',
    'note',
    'notes',
    'journal',
  };

  @override
  Future<ReminderDraftParseResult> parseText(
    String input,
    ReminderDraftContext context,
  ) async {
    final String trimmed = input.trim();
    if (trimmed.isEmpty || _looksUnclear(trimmed)) {
      return const ReminderDraftParseResult(
        drafts: <ParsedReminderDraft>[],
        isUnclear: true,
      );
    }
    _rejectBlockedKinds(trimmed);
    return ReminderDraftParseResult(
      drafts: _splitItems(trimmed)
          .map((String item) => _draftFromText(item, context))
          .toList(growable: false),
      rawTranscript: trimmed,
    );
  }

  @override
  Future<ReminderDraftParseResult> parseAudio(
    File file,
    ReminderDraftContext context,
  ) async {
    if (!await file.exists()) {
      throw ReminderDraftFormatException(
        'Audio file was not found: ${file.path}',
      );
    }
    final String transcript = await file.readAsString();
    final ReminderDraftParseResult parsed = await parseText(
      transcript,
      context,
    );
    return ReminderDraftParseResult(
      drafts: parsed.drafts,
      rawTranscript: transcript.trim(),
      isUnclear: parsed.isUnclear,
    );
  }

  static bool _looksUnclear(String input) {
    final String lower = input.toLowerCase();
    return lower.length < 4 ||
        lower.contains('unclear') ||
        lower.contains('inaudible') ||
        lower.contains('???');
  }

  static void _rejectBlockedKinds(String input) {
    final Set<String> words = input
        .toLowerCase()
        .split(RegExp(r'[^a-z]+'))
        .where((String word) => word.isNotEmpty)
        .toSet();
    final Iterable<String> rejected = words.where(_blockedKinds.contains);
    if (rejected.isNotEmpty) {
      throw ReminderDraftFormatException(
        'Reminder drafting only accepts task reminders, not ${rejected.first}.',
      );
    }
  }

  static List<String> _splitItems(String input) {
    final String normalized = input.replaceAll(RegExp(r'\s+'), ' ').trim();
    final List<String> pieces = normalized
        .split(
          RegExp(r'\s*(?:;|\n|\band then\b|\balso\b)\s+', caseSensitive: false),
        )
        .map(_cleanTitle)
        .where((String item) => item.isNotEmpty)
        .toList(growable: false);
    return pieces.isEmpty ? <String>[_cleanTitle(normalized)] : pieces;
  }

  static ParsedReminderDraft _draftFromText(
    String input,
    ReminderDraftContext context,
  ) {
    final String lower = input.toLowerCase();
    final DateTime? scheduledAt = _scheduledAt(lower, context.now);
    final bool place =
        lower.contains(' at home') ||
        lower.contains(' at work') ||
        lower.contains(' when i arrive') ||
        lower.contains(' when i leave');
    final double confidence =
        lower.contains('maybe') || lower.contains('sometime')
        ? 0.52
        : scheduledAt == null && !place
        ? 0.64
        : 0.88;
    final TaskReminderTriggerType triggerType = place && scheduledAt == null
        ? TaskReminderTriggerType.place
        : TaskReminderTriggerType.time;
    final GeofenceTransition? transition = place
        ? lower.contains('leave')
              ? GeofenceTransition.exit
              : GeofenceTransition.enter
        : null;
    return ParsedReminderDraft(
      title: _cleanTitle(input),
      details: input,
      confidence: confidence,
      triggerType: triggerType,
      scheduledAt: triggerType == TaskReminderTriggerType.time
          ? scheduledAt
          : null,
      placeCandidate: place ? _placeCandidate(lower) : null,
      geofenceTransition: transition,
      dwellSeconds: place ? 60 : null,
      explanation: scheduledAt != null
          ? 'Detected a time trigger from the reminder text.'
          : place
          ? 'Detected a place trigger, but it needs a saved place before activation.'
          : 'No clear trigger was detected.',
    );
  }

  static DateTime? _scheduledAt(String lower, DateTime now) {
    if (lower.contains('tomorrow')) {
      return DateTime.utc(now.year, now.month, now.day + 1, 9);
    }
    if (lower.contains('tonight')) {
      return DateTime.utc(now.year, now.month, now.day, 20);
    }
    if (lower.contains('today')) {
      return now.add(const Duration(hours: 2));
    }
    final RegExpMatch? hour = RegExp(
      r'\bat\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b',
    ).firstMatch(lower);
    if (hour == null) return null;
    int h = int.parse(hour.group(1)!);
    final int minute = int.tryParse(hour.group(2) ?? '0') ?? 0;
    final String? period = hour.group(3);
    if (period == 'pm' && h < 12) h += 12;
    if (period == 'am' && h == 12) h = 0;
    final DateTime candidate = DateTime.utc(
      now.year,
      now.month,
      now.day,
      h,
      minute,
    );
    return candidate.isAfter(now)
        ? candidate
        : candidate.add(const Duration(days: 1));
  }

  static String _placeCandidate(String lower) {
    if (lower.contains('home')) return 'home';
    if (lower.contains('work')) return 'work';
    return 'saved place';
  }

  static String _cleanTitle(String input) {
    return input
        .trim()
        .replaceFirst(RegExp(r'^remind me to\s+', caseSensitive: false), '')
        .replaceFirst(RegExp(r'^remember to\s+', caseSensitive: false), '')
        .trim();
  }
}

class GeminiReminderDraftService implements ReminderDraftService {
  const GeminiReminderDraftService({
    required this.apiKey,
    required this.model,
    this.fallback = const HeuristicReminderDraftService(),
  });

  final String apiKey;
  final String model;
  final ReminderDraftService fallback;

  @override
  Future<ReminderDraftParseResult> parseText(
    String input,
    ReminderDraftContext context,
  ) async {
    if (apiKey.isEmpty) {
      return fallback.parseText(input, context);
    }
    return _parseWithGemini(
      prompt: _prompt(context),
      userText: input,
      context: context,
    );
  }

  @override
  Future<ReminderDraftParseResult> parseAudio(
    File file,
    ReminderDraftContext context,
  ) async {
    if (!await file.exists()) {
      throw ReminderDraftFormatException(
        'Audio file was not found: ${file.path}',
      );
    }
    if (apiKey.isEmpty) {
      return fallback.parseAudio(file, context);
    }
    return _parseWithGemini(
      prompt: _prompt(context),
      audioFile: file,
      context: context,
    );
  }

  Future<ReminderDraftParseResult> _parseWithGemini({
    required String prompt,
    required ReminderDraftContext context,
    String? userText,
    File? audioFile,
  }) async {
    final Uri uri = Uri.https(
      'generativelanguage.googleapis.com',
      '/v1beta/models/$model:generateContent',
      <String, String>{'key': apiKey},
    );
    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode(<String, Object?>{
          'contents': <Object?>[
            <String, Object?>{
              'role': 'user',
              'parts': <Object?>[
                <String, Object?>{'text': prompt},
                if (userText != null) <String, Object?>{'text': userText},
                if (audioFile != null)
                  <String, Object?>{
                    'inlineData': <String, Object?>{
                      'mimeType': _mimeType(audioFile.path),
                      'data': base64Encode(await audioFile.readAsBytes()),
                    },
                  },
              ],
            },
          ],
          'generationConfig': <String, Object?>{
            'temperature': 0.1,
            'responseMimeType': 'application/json',
          },
        }),
      );
      final HttpClientResponse response = await request.close();
      final String body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ReminderDraftFormatException(
          'Gemini reminder drafting failed (${response.statusCode}).',
        );
      }
      return _parseGeminiBody(body, context);
    } finally {
      client.close(force: true);
    }
  }

  ReminderDraftParseResult _parseGeminiBody(
    String body,
    ReminderDraftContext context,
  ) {
    final Object? decoded = jsonDecode(body);
    final Map<String, Object?> root = Map<String, Object?>.from(decoded as Map);
    final List<Object?> candidates = List<Object?>.from(
      root['candidates'] as List? ?? const <Object?>[],
    );
    if (candidates.isEmpty) {
      return const ReminderDraftParseResult(
        drafts: <ParsedReminderDraft>[],
        isUnclear: true,
      );
    }
    final Map<String, Object?> candidate = Map<String, Object?>.from(
      candidates.first as Map,
    );
    final Map<String, Object?> content = Map<String, Object?>.from(
      candidate['content'] as Map? ?? const <String, Object?>{},
    );
    final List<Object?> parts = List<Object?>.from(
      content['parts'] as List? ?? const <Object?>[],
    );
    final String text = parts
        .map((Object? part) => Map<String, Object?>.from(part as Map)['text'])
        .whereType<String>()
        .join('\n')
        .trim();
    if (text.isEmpty) {
      return const ReminderDraftParseResult(
        drafts: <ParsedReminderDraft>[],
        isUnclear: true,
      );
    }
    return _parseDraftJson(_stripJsonFence(text), context);
  }

  ReminderDraftParseResult _parseDraftJson(
    String raw,
    ReminderDraftContext context,
  ) {
    final Object? decoded = jsonDecode(raw);
    final Map<String, Object?> root = Map<String, Object?>.from(decoded as Map);
    final bool unclear = root['is_unclear'] == true;
    final String? rawTranscript = root['raw_transcript'] as String?;
    final List<Object?> items = List<Object?>.from(
      root['drafts'] as List? ?? const <Object?>[],
    );
    if (unclear || items.isEmpty) {
      return ReminderDraftParseResult(
        drafts: const <ParsedReminderDraft>[],
        rawTranscript: rawTranscript,
        isUnclear: true,
      );
    }
    return ReminderDraftParseResult(
      drafts: items
          .map((Object? item) => _draftFromJson(item, context))
          .toList(growable: false),
      rawTranscript: rawTranscript,
    );
  }

  ParsedReminderDraft _draftFromJson(
    Object? value,
    ReminderDraftContext context,
  ) {
    final Map<String, Object?> json = Map<String, Object?>.from(value as Map);
    final String kind = (json['kind'] as String? ?? 'task_reminder')
        .toLowerCase();
    if (kind != 'task_reminder') {
      throw ReminderDraftFormatException(
        'Reminder drafting only accepts task reminders, not $kind.',
      );
    }
    final String trigger = (json['trigger_type'] as String? ?? 'time')
        .toLowerCase();
    final String? scheduledRaw = json['scheduled_at'] as String?;
    final String? transitionRaw = json['geofence_transition'] as String?;
    return ParsedReminderDraft(
      title: json['title'] as String? ?? 'Untitled reminder',
      details: json['details'] as String?,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      triggerType: trigger == 'place'
          ? TaskReminderTriggerType.place
          : TaskReminderTriggerType.time,
      scheduledAt: scheduledRaw == null || scheduledRaw.isEmpty
          ? null
          : DateTime.tryParse(scheduledRaw)?.toUtc(),
      placeId: json['place_id'] as String?,
      placeCandidate: json['place_candidate'] as String?,
      geofenceTransition: GeofenceTransition.fromWire(transitionRaw),
      dwellSeconds: (json['dwell_seconds'] as num?)?.toInt(),
      explanation:
          json['explanation'] as String? ?? 'AI parsed a task reminder draft.',
    );
  }

  static String _prompt(ReminderDraftContext context) =>
      '''
You extract Sidekick POC task reminders only.
Return strict JSON with this shape:
{
  "is_unclear": false,
  "raw_transcript": "verbatim transcript if audio",
  "drafts": [
    {
      "kind": "task_reminder",
      "title": "short action",
      "details": "optional details",
      "confidence": 0.0,
      "trigger_type": "time|place",
      "scheduled_at": "UTC ISO-8601 or null",
      "place_id": null,
      "place_candidate": "home/work/etc or null",
      "geofence_transition": "enter|exit|null",
      "dwell_seconds": 60,
      "explanation": "brief reason"
    }
  ]
}
Never output habits, goals, notes, journal entries, or proactive suggestions.
If the input is unclear, set is_unclear true and drafts to [].
Current UTC time: ${context.now.toIso8601String()}.
Audio retry count: ${context.audioRetryCount}.
''';

  static String _stripJsonFence(String text) {
    final String trimmed = text.trim();
    if (!trimmed.startsWith('```')) return trimmed;
    return trimmed
        .replaceFirst(RegExp(r'^```(?:json)?\s*', caseSensitive: false), '')
        .replaceFirst(RegExp(r'\s*```$'), '')
        .trim();
  }

  static String _mimeType(String path) {
    final String lower = path.toLowerCase();
    if (lower.endsWith('.m4a')) return 'audio/mp4';
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.wav')) return 'audio/wav';
    if (lower.endsWith('.ogg')) return 'audio/ogg';
    if (lower.endsWith('.webm')) return 'audio/webm';
    if (lower.endsWith('.aac')) return 'audio/aac';
    return 'application/octet-stream';
  }
}
