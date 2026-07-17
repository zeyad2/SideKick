import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sidekick/core/domain/enums.dart';

@immutable
class CaptureAnalysis {
  const CaptureAnalysis({
    required this.type,
    required this.title,
    required this.details,
    required this.suggestedSchedule,
    required this.rawTranscript,
  });

  factory CaptureAnalysis.parse(String responseText) {
    final String cleaned = responseText
        .trim()
        .replaceFirst(RegExp(r'^```(?:json)?\s*', caseSensitive: false), '')
        .replaceFirst(RegExp(r'\s*```$'), '')
        .trim();
    final Object? decoded;
    try {
      decoded = jsonDecode(cleaned);
    } on FormatException catch (error) {
      throw CaptureAnalysisFormatException(
        'Gemini returned invalid JSON.',
        error,
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw const CaptureAnalysisFormatException(
        'Gemini JSON must be an object.',
      );
    }
    return CaptureAnalysis.fromJson(decoded);
  }

  factory CaptureAnalysis.fromJson(Map<String, Object?> json) {
    const Set<String> required = <String>{
      'type',
      'title',
      'details',
      'suggested_schedule',
      'raw_transcript',
    };
    if (!json.keys.toSet().containsAll(required)) {
      throw const CaptureAnalysisFormatException(
        'Gemini JSON is missing one or more required fields.',
      );
    }
    final Object? typeValue = json['type'];
    final Object? titleValue = json['title'];
    final Object? detailsValue = json['details'];
    final Object? transcriptValue = json['raw_transcript'];
    final Object? scheduleValue = json['suggested_schedule'];
    if (typeValue is! String ||
        titleValue is! String ||
        detailsValue is! String ||
        transcriptValue is! String ||
        (scheduleValue != null && scheduleValue is! Map)) {
      throw const CaptureAnalysisFormatException(
        'Gemini JSON contains invalid field types.',
      );
    }
    final LlmType type = LlmType.fromWire(typeValue);
    if (type == LlmType.uncategorized ||
        titleValue.trim().isEmpty ||
        transcriptValue.trim().isEmpty) {
      throw const CaptureAnalysisFormatException(
        'Gemini JSON contains invalid semantic values.',
      );
    }
    return CaptureAnalysis(
      type: type,
      title: titleValue.trim(),
      details: detailsValue.trim(),
      suggestedSchedule: scheduleValue == null
          ? null
          : Map<String, Object?>.from(scheduleValue as Map),
      rawTranscript: transcriptValue.trim(),
    );
  }

  final LlmType type;
  final String title;
  final String details;
  final Map<String, Object?>? suggestedSchedule;
  final String rawTranscript;
}

class CaptureAnalysisFormatException implements Exception {
  const CaptureAnalysisFormatException(this.message, [this.cause]);
  final String message;
  final Object? cause;

  @override
  String toString() => 'CaptureAnalysisFormatException: $message';
}
