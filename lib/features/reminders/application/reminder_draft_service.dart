import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:sidekick/core/domain/enums.dart';
import 'package:sidekick/features/reminders/application/assistant_context_builder.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

@immutable
class ReminderDraftContext {
  const ReminderDraftContext({
    required this.now,
    this.audioRetryCount = 0,
    this.assistantContext,
    this.timeZoneName = 'UTC',
  });

  final DateTime now;
  final int audioRetryCount;
  final AssistantContext? assistantContext;
  final String timeZoneName;
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
    this.draftId,
    this.details,
    this.scheduledAt,
    this.placeId,
    this.placeCandidate,
    this.geofenceTransition,
    this.dwellSeconds,
    this.contextItemsUsed = const <String>[],
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
  final String? draftId;
  final List<String> contextItemsUsed;

  bool get hasConcreteTrigger => switch (triggerType) {
    TaskReminderTriggerType.time => scheduledAt != null,
    TaskReminderTriggerType.place => placeId != null,
  };

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': 'task_reminder',
    'draft_id': draftId,
    'title': title,
    'details': details,
    'confidence': confidence,
    'trigger_type': triggerType.wire,
    'scheduled_at': scheduledAt?.toUtc().toIso8601String(),
    'place_id': placeId,
    'place_candidate': placeCandidate,
    'geofence_transition': geofenceTransition?.wire,
    'dwell_seconds': dwellSeconds,
    'explanation': explanation,
    'context_items_used': contextItemsUsed,
  };

  static ParsedReminderDraft fromJson(Map<String, Object?> json) {
    final String trigger = json['trigger_type'] as String? ?? 'time';
    final String? scheduledRaw = json['scheduled_at'] as String?;
    final String? transitionRaw = json['geofence_transition'] as String?;
    return ParsedReminderDraft(
      title: json['title'] as String? ?? '',
      draftId: json['draft_id'] as String?,
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
      contextItemsUsed: List<Object?>.from(
        json['context_items_used'] as List? ?? const <Object?>[],
      ).whereType<String>().toList(growable: false),
    );
  }
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

  static bool _timeZonesInitialized = false;

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
    final DateTime? scheduledAt = _scheduledAt(lower, context);
    final Map<String, Object?>? matchedPlace = _matchedPlace(lower, context);
    final bool wrongPlaceFeedback = _hasWrongPlaceFeedback(
      matchedPlace?['id'] as String?,
      context,
    );
    final bool place =
        matchedPlace != null ||
        lower.contains(' at home') ||
        lower.contains(' at work') ||
        lower.contains(' when i arrive') ||
        lower.contains(' when i leave');
    final double confidence =
        lower.contains('maybe') || lower.contains('sometime')
        ? 0.52
        : wrongPlaceFeedback
        ? 0.62
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
      draftId: null,
      details: input,
      confidence: confidence,
      triggerType: triggerType,
      scheduledAt: triggerType == TaskReminderTriggerType.time
          ? scheduledAt
          : null,
      placeId: matchedPlace?['id'] as String?,
      placeCandidate: place
          ? (matchedPlace?['name'] as String? ?? _placeCandidate(lower))
          : null,
      geofenceTransition: transition,
      dwellSeconds: place ? 60 : null,
      explanation: scheduledAt != null
          ? 'Detected a time trigger from the reminder text.'
          : wrongPlaceFeedback
          ? 'Matched a saved place, but recent Wrong place feedback means this needs review.'
          : matchedPlace != null
          ? 'Matched the place trigger to a saved place from life context.'
          : place
          ? 'Detected a place trigger, but it needs a saved place before activation.'
          : 'No clear trigger was detected.',
      contextItemsUsed: matchedPlace == null
          ? const <String>[]
          : <String>['place:${matchedPlace['id']}'],
    );
  }

  static DateTime? _scheduledAt(String lower, ReminderDraftContext context) {
    final DateTime now = context.now.toUtc();
    final tz.Location location = _locationForZone(context.timeZoneName);
    final tz.TZDateTime localNow = tz.TZDateTime.from(now, location);
    DateTime local(int year, int month, int day, int hour, [int minute = 0]) =>
        tz.TZDateTime(location, year, month, day, hour, minute).toUtc();
    if (lower.contains('tomorrow')) {
      return local(localNow.year, localNow.month, localNow.day + 1, 9);
    }
    if (lower.contains('tonight')) {
      return local(localNow.year, localNow.month, localNow.day, 20);
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
    final DateTime candidate = local(
      localNow.year,
      localNow.month,
      localNow.day,
      h,
      minute,
    );
    return candidate.isAfter(now)
        ? candidate
        : local(localNow.year, localNow.month, localNow.day + 1, h, minute);
  }

  static tz.Location _locationForZone(String zone) {
    if (!_timeZonesInitialized) {
      tz_data.initializeTimeZones();
      _timeZonesInitialized = true;
    }
    try {
      return tz.getLocation(zone);
    } catch (_) {
      return tz.UTC;
    }
  }

  static String _placeCandidate(String lower) {
    if (lower.contains('home')) return 'home';
    if (lower.contains('work')) return 'work';
    return 'saved place';
  }

  static Map<String, Object?>? _matchedPlace(
    String lower,
    ReminderDraftContext context,
  ) {
    final AssistantContext? assistantContext = context.assistantContext;
    if (assistantContext == null) return null;
    for (final Map<String, Object?> place in assistantContext.places) {
      final String name = (place['name'] as String? ?? '').toLowerCase();
      if (name.isNotEmpty && lower.contains(name)) {
        return place;
      }
    }
    return null;
  }

  static bool _hasWrongPlaceFeedback(
    String? placeId,
    ReminderDraftContext context,
  ) {
    if (placeId == null) return false;
    final AssistantContext? assistantContext = context.assistantContext;
    if (assistantContext == null) return false;
    for (final Map<String, Object?> event
        in assistantContext.recentReminderActions) {
      if (event['event_type'] != 'wrong_place') continue;
      final Object? metadata = event['metadata'];
      if (metadata is Map && metadata['place_id'] == placeId) {
        return true;
      }
    }
    return false;
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

  @visibleForTesting
  ReminderDraftParseResult parseGeminiResponseForTesting(
    String body,
    ReminderDraftContext context,
  ) => _parseGeminiBody(body, context);

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
    return validateDraftJson(json, context);
  }

  @visibleForTesting
  static ParsedReminderDraft validateDraftJson(
    Map<String, Object?> json,
    ReminderDraftContext context,
  ) {
    final String? rawKind = json['kind'] as String?;
    if (rawKind == null || rawKind.isEmpty) {
      throw const ReminderDraftFormatException(
        'Reminder drafts must include kind.',
      );
    }
    final String kind = rawKind.toLowerCase();
    if (kind != 'task_reminder') {
      throw ReminderDraftFormatException(
        'Reminder drafting only accepts task reminders, not $kind.',
      );
    }
    final String? title = (json['title'] as String?)?.trim();
    if (title == null || title.isEmpty) {
      throw const ReminderDraftFormatException(
        'Reminder drafts must include a title.',
      );
    }
    final String? explanation = (json['explanation'] as String?)?.trim();
    if (explanation == null || explanation.isEmpty) {
      throw const ReminderDraftFormatException(
        'Reminder drafts must include a non-empty explanation.',
      );
    }
    final num? confidenceNum = json['confidence'] as num?;
    final double? confidence = confidenceNum?.toDouble();
    if (confidence == null ||
        !confidence.isFinite ||
        confidence < 0 ||
        confidence > 1) {
      throw const ReminderDraftFormatException(
        'Reminder confidence must be finite and between 0 and 1.',
      );
    }
    final String? rawTrigger = json['trigger_type'] as String?;
    final TaskReminderTriggerType triggerType = switch (rawTrigger) {
      'time' => TaskReminderTriggerType.time,
      'place' => TaskReminderTriggerType.place,
      _ => throw ReminderDraftFormatException(
        'Reminder trigger_type must be time or place, not $rawTrigger.',
      ),
    };
    final String? scheduledRaw = json['scheduled_at'] as String?;
    final String? transitionRaw = json['geofence_transition'] as String?;
    final DateTime? scheduledAt = scheduledRaw == null || scheduledRaw.isEmpty
        ? null
        : DateTime.tryParse(scheduledRaw)?.toUtc();
    if (scheduledRaw != null &&
        scheduledRaw.isNotEmpty &&
        !_hasTimezoneQualifier(scheduledRaw)) {
      throw ReminderDraftFormatException(
        'Reminder scheduled_at must include a timezone: $scheduledRaw.',
      );
    }
    if (scheduledRaw != null &&
        scheduledRaw.isNotEmpty &&
        scheduledAt == null) {
      throw ReminderDraftFormatException(
        'Reminder scheduled_at is not a valid timestamp: $scheduledRaw.',
      );
    }
    final GeofenceTransition? transition = switch (transitionRaw) {
      null || '' => null,
      'enter' => GeofenceTransition.enter,
      'exit' => GeofenceTransition.exit,
      _ => throw ReminderDraftFormatException(
        'Reminder geofence_transition must be enter or exit, not $transitionRaw.',
      ),
    };
    final int? dwellSeconds = (json['dwell_seconds'] as num?)?.toInt();
    if (dwellSeconds != null && dwellSeconds < 0) {
      throw const ReminderDraftFormatException(
        'Reminder dwell_seconds must be zero or greater.',
      );
    }
    final String? placeId = json['place_id'] as String?;
    if (triggerType == TaskReminderTriggerType.time) {
      if (scheduledAt == null) {
        throw const ReminderDraftFormatException(
          'Time reminders must include scheduled_at.',
        );
      }
      if (placeId != null || transition != null) {
        throw const ReminderDraftFormatException(
          'Time reminders cannot include place fields.',
        );
      }
    } else {
      if (scheduledAt != null) {
        throw const ReminderDraftFormatException(
          'Place reminders cannot include scheduled_at.',
        );
      }
      if (placeId != null && transition == null) {
        throw const ReminderDraftFormatException(
          'Place reminders with place_id must include geofence_transition.',
        );
      }
    }
    final Set<String> allowedContextIds = _allowedContextIds(
      context.assistantContext,
    );
    if (placeId != null && !allowedContextIds.contains('place:$placeId')) {
      throw ReminderDraftFormatException(
        'AI returned place_id that was not supplied in context: $placeId.',
      );
    }
    final Object? rawContextItems = json['context_items_used'];
    if (rawContextItems != null && rawContextItems is! List) {
      throw const ReminderDraftFormatException(
        'context_items_used must be a list of strings.',
      );
    }
    final List<String> contextItemsUsed = <String>[];
    for (final Object? item in List<Object?>.from(
      rawContextItems as List? ?? const <Object?>[],
    )) {
      if (item is! String || item.isEmpty) {
        throw const ReminderDraftFormatException(
          'context_items_used must contain only non-empty strings.',
        );
      }
      contextItemsUsed.add(item);
    }
    for (final String itemId in contextItemsUsed) {
      if (!allowedContextIds.contains(itemId)) {
        throw ReminderDraftFormatException(
          'AI returned context item that was not supplied: $itemId.',
        );
      }
    }
    return ParsedReminderDraft(
      title: title,
      draftId: json['draft_id'] as String?,
      details: json['details'] as String?,
      confidence: confidence,
      triggerType: triggerType,
      scheduledAt: scheduledAt,
      placeId: placeId,
      placeCandidate: json['place_candidate'] as String?,
      geofenceTransition: transition,
      dwellSeconds: dwellSeconds,
      explanation: explanation,
      contextItemsUsed: contextItemsUsed,
    );
  }

  static bool _hasTimezoneQualifier(String value) =>
      value.endsWith('Z') || RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(value);

  static Set<String> _allowedContextIds(AssistantContext? context) {
    if (context == null) return const <String>{};
    return <String>{
      for (final Map<String, Object?> place in context.places)
        if (place['id'] case final String id) 'place:$id',
      for (final Map<String, Object?> reminder in context.activeReminders)
        if (reminder['id'] case final String id) 'reminder:$id',
      for (final Map<String, Object?> event in context.recentReminderActions)
        if (event['id'] case final String id) 'reminder_event:$id',
      for (final Map<String, Object?> capture in context.recentUnclearCaptures)
        if (capture['id'] case final String id) 'capture:$id',
    };
  }

  @visibleForTesting
  static String promptForTesting(ReminderDraftContext context) =>
      _prompt(context);

  static String _prompt(ReminderDraftContext context) {
    final String contextJson = jsonEncode(
      context.assistantContext?.toJson() ?? const <String, Object?>{},
    );
    return '''
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
      "explanation": "brief reason for the selected trigger",
      "context_items_used": []
    }
  ]
}
Never output habits, goals, notes, journal entries, or proactive suggestions.
Do not create reminders from background context; only parse the user's explicit
typed or audio request. If the user's input is empty or only asks for a chat
reply, set is_unclear true and drafts to [].
Use the assistant context only to resolve ambiguity in that explicit request.
Prefer saved place IDs over place_candidate text when a user mentions a saved
place name or nickname. Do not infer new reminders from active reminders,
recent actions, or unclear captures.
When context influenced a field, list stable item IDs in context_items_used
using these prefixes: place:<id>, reminder:<id>, reminder_event:<id>,
capture:<id>. Do not include an ID unless it appears in the context JSON.
If the input is unclear, set is_unclear true and drafts to [].
Current UTC time: ${context.now.toIso8601String()}.
Audio retry count: ${context.audioRetryCount}.
Assistant context JSON, bounded and redacted:
$contextJson
''';
  }

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
