import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sidekick/features/inbox/domain/capture_analysis.dart';

/// Frozen P4 Gemini boundary, reused by later intelligence features.
abstract interface class GeminiClient {
  Future<CaptureAnalysis> analyzeCaptureAudio(File audioFile);
}

abstract interface class GeminiTransport {
  Future<Map<String, Object?>> postJson({
    required Uri uri,
    required Map<String, String> headers,
    required Map<String, Object?> body,
  });
}

class IoGeminiTransport implements GeminiTransport {
  IoGeminiTransport({HttpClient? client}) : _client = client ?? HttpClient();
  final HttpClient _client;

  @override
  Future<Map<String, Object?>> postJson({
    required Uri uri,
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) async {
    final HttpClientRequest request = await _client.postUrl(uri);
    headers.forEach(request.headers.set);
    // Encode as UTF-8 explicitly: HttpClientRequest.write defaults to Latin-1,
    // which throws on the non-Latin-1 characters (em dashes, ellipses, curly
    // quotes) in the prompt.
    request.add(utf8.encode(jsonEncode(body)));
    final HttpClientResponse response = await request.close().timeout(
      const Duration(seconds: 45),
    );
    final String payload = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GeminiRequestException(
        'Gemini HTTP ${response.statusCode}.',
        transient:
            response.statusCode == 408 ||
            response.statusCode == 429 ||
            response.statusCode >= 500,
      );
    }
    final Object? decoded = jsonDecode(payload);
    if (decoded is! Map<String, Object?>) {
      throw const GeminiRequestException('Gemini response was not an object.');
    }
    return decoded;
  }
}

class GeminiFlashClient implements GeminiClient {
  GeminiFlashClient({
    required this.apiKey,
    required this.model,
    GeminiTransport? transport,
    this.maxAttempts = 3,
    Future<void> Function(Duration)? delay,
  }) : _transport = transport ?? IoGeminiTransport(),
       _delay = delay ?? Future<void>.delayed;

  final String apiKey;
  final String model;
  final int maxAttempts;
  final GeminiTransport _transport;
  final Future<void> Function(Duration) _delay;

  @override
  Future<CaptureAnalysis> analyzeCaptureAudio(File audioFile) async {
    if (apiKey.isEmpty) {
      throw const GeminiRequestException('GEMINI_API_KEY is not configured.');
    }
    if (!audioFile.existsSync()) {
      throw const GeminiRequestException('Captured audio file is missing.');
    }
    final List<int> bytes = await audioFile.readAsBytes();
    if (bytes.isEmpty) {
      throw const GeminiRequestException('Captured audio file is empty.');
    }
    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt += 1) {
      try {
        final Map<String, Object?> response = await _transport.postJson(
          uri: Uri.https(
            'generativelanguage.googleapis.com',
            '/v1beta/models/$model:generateContent',
          ),
          headers: <String, String>{
            'content-type': 'application/json',
            'x-goog-api-key': apiKey,
          },
          body: _requestBody(bytes, _mimeType(audioFile.path)),
        );
        return CaptureAnalysis.parse(_responseText(response));
      } catch (error) {
        lastError = error;
        final bool transient =
            error is SocketException ||
            error is TimeoutException ||
            (error is GeminiRequestException && error.transient) ||
            error is CaptureAnalysisFormatException;
        if (!transient || attempt == maxAttempts) rethrow;
        await _delay(Duration(milliseconds: 300 * attempt));
      }
    }
    throw GeminiRequestException('Gemini request failed: $lastError');
  }

  Map<String, Object?> _requestBody(List<int> bytes, String mimeType) =>
      <String, Object?>{
        'contents': <Object?>[
          <String, Object?>{
            'role': 'user',
            'parts': <Object?>[
              <String, Object?>{'text': _prompt},
              <String, Object?>{
                'inlineData': <String, Object?>{
                  'mimeType': mimeType,
                  'data': base64Encode(bytes),
                },
              },
            ],
          },
        ],
        'generationConfig': <String, Object?>{
          'temperature': 0.1,
          'responseMimeType': 'application/json',
          'responseSchema': _responseSchema,
        },
      };

  // A rant usually holds SEVERAL distinct things; the model breaks them apart
  // into one draft item per thing. The kind rule and the no-cross-propagation
  // rule mirror docs/CAPTURE_DECOMPOSITION.md §2 and §10/§12.3 — the latter is
  // load-bearing for auto-commit trust.
  static const String _prompt =
      'You are decomposing a spoken brain-dump (a "rant") into distinct '
      'actionable items. The speaker may use Egyptian Arabic, Arabizi, English, '
      'or code-switching.\n'
      '\n'
      'Return an object with:\n'
      '- raw_transcript: the full spoken content, meaning preserved (original '
      'language is fine).\n'
      '- items: an array with ONE element per distinct thing the speaker '
      'mentioned. Titles and details must be concise English.\n'
      '\n'
      'Classify each item into exactly one kind:\n'
      '- task: a discrete, completable action (has a "done"). Default for '
      'anything actionable.\n'
      '- habit: a recurring behavior where success is consistency, not '
      'completion.\n'
      '- goal: a longer-horizon outcome you work toward; do NOT over-detect — '
      'a typical rant has none.\n'
      '- note: a thought or reference with no action.\n'
      '\n'
      'Fill ONLY the fields relevant to the chosen kind. Set confidence to '
      '"high" only when the wording is unambiguous; otherwise "low".\n'
      '\n'
      'CRITICAL: do NOT copy context between items. A location, date, or '
      'trigger the speaker attached to one item must not be applied to any '
      'other item unless the speaker clearly said it for that item too. When in '
      'doubt, leave the sibling item plain.\n'
      '\n'
      'If the rant contains nothing actionable or notable, return an empty '
      'items array (do not invent content).';

  static const Map<String, Object?> _responseSchema = <String, Object?>{
    'type': 'OBJECT',
    'properties': <String, Object?>{
      'raw_transcript': <String, Object?>{'type': 'STRING'},
      'items': <String, Object?>{
        'type': 'ARRAY',
        'items': <String, Object?>{
          'type': 'OBJECT',
          'properties': <String, Object?>{
            'kind': <String, Object?>{
              'type': 'STRING',
              'enum': <String>['task', 'note', 'habit', 'goal'],
            },
            'title': <String, Object?>{'type': 'STRING'},
            'details': <String, Object?>{'type': 'STRING', 'nullable': true},
            'confidence': <String, Object?>{
              'type': 'STRING',
              'enum': <String>['high', 'low'],
            },
            // task only
            'schedule': <String, Object?>{
              'type': 'OBJECT',
              'nullable': true,
              'properties': <String, Object?>{
                'date': <String, Object?>{'type': 'STRING', 'nullable': true},
                'time': <String, Object?>{'type': 'STRING', 'nullable': true},
              },
            },
            'location': <String, Object?>{
              'type': 'OBJECT',
              'nullable': true,
              'properties': <String, Object?>{
                'name': <String, Object?>{'type': 'STRING'},
                'transition': <String, Object?>{
                  'type': 'STRING',
                  'nullable': true,
                  'enum': <String>['enter', 'exit'],
                },
              },
            },
            'reminder': <String, Object?>{'type': 'BOOLEAN', 'nullable': true},
            // habit only
            'anchor': <String, Object?>{'type': 'STRING', 'nullable': true},
            'cadence': <String, Object?>{
              'type': 'OBJECT',
              'nullable': true,
              'properties': <String, Object?>{
                'type': <String, Object?>{'type': 'STRING'},
                'days': <String, Object?>{
                  'type': 'ARRAY',
                  'nullable': true,
                  'items': <String, Object?>{'type': 'STRING'},
                },
                'per_week': <String, Object?>{
                  'type': 'INTEGER',
                  'nullable': true,
                },
              },
            },
            'level': <String, Object?>{
              'type': 'STRING',
              'nullable': true,
              'enum': <String>['mini', 'normal', 'mega'],
            },
            // goal only
            'why': <String, Object?>{'type': 'STRING', 'nullable': true},
            'target_date': <String, Object?>{
              'type': 'STRING',
              'nullable': true,
            },
          },
          'required': <String>['kind', 'title', 'confidence'],
        },
      },
    },
    'required': <String>['raw_transcript', 'items'],
  };

  static String _responseText(Map<String, Object?> response) {
    try {
      final List<Object?> candidates = response['candidates']! as List<Object?>;
      final Map<String, Object?> candidate =
          candidates.first! as Map<String, Object?>;
      final Map<String, Object?> content =
          candidate['content']! as Map<String, Object?>;
      final List<Object?> parts = content['parts']! as List<Object?>;
      final Map<String, Object?> part = parts.first! as Map<String, Object?>;
      return part['text']! as String;
    } catch (error) {
      throw CaptureAnalysisFormatException(
        'Gemini response envelope was malformed.',
        error,
      );
    }
  }

  static String _mimeType(String path) {
    final String extension = path.split('.').last.toLowerCase();
    return switch (extension) {
      'aac' => 'audio/aac',
      'm4a' => 'audio/mp4',
      'mp3' => 'audio/mpeg',
      'wav' => 'audio/wav',
      'ogg' => 'audio/ogg',
      _ => 'application/octet-stream',
    };
  }
}

class GeminiRequestException implements Exception {
  const GeminiRequestException(this.message, {this.transient = false});
  final String message;
  final bool transient;

  @override
  String toString() => 'GeminiRequestException: $message';
}
