import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sidekick/features/inbox/domain/proposed_item.dart';

/// The result of decomposing a rant (docs/CAPTURE_DECOMPOSITION.md §10 — the
/// deliberately-unfrozen P4 boundary). Carries the full transcript at capture
/// level plus an **ordered list of draft items** (§4). The list may be empty —
/// the processing service applies the single-`note` fallback (§11) rather than
/// this parser inventing content.
@immutable
class CaptureAnalysis {
  const CaptureAnalysis({required this.rawTranscript, required this.items});

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
    final Object? transcriptValue = json['raw_transcript'];
    if (transcriptValue is! String || transcriptValue.trim().isEmpty) {
      throw const CaptureAnalysisFormatException(
        'Gemini JSON is missing a non-empty `raw_transcript`.',
      );
    }
    final Object? itemsValue = json['items'];
    if (itemsValue is! List) {
      throw const CaptureAnalysisFormatException(
        'Gemini JSON `items` must be an array.',
      );
    }
    final List<ProposedItem> items;
    try {
      items = itemsValue
          .map<ProposedItem>(ProposedItem.fromGemini)
          .toList(growable: false);
    } on ProposedItemFormatException catch (error) {
      throw CaptureAnalysisFormatException(
        'Gemini JSON contains an invalid draft item.',
        error,
      );
    }
    return CaptureAnalysis(rawTranscript: transcriptValue, items: items);
  }

  final String rawTranscript;
  final List<ProposedItem> items;
}

class CaptureAnalysisFormatException implements Exception {
  const CaptureAnalysisFormatException(this.message, [this.cause]);
  final String message;
  final Object? cause;

  @override
  String toString() => 'CaptureAnalysisFormatException: $message';
}
