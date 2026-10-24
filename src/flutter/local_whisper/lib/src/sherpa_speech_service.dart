import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'models.dart';

/// Model ids transcribed by sherpa-onnx in Dart on Android and iOS.
bool isSherpaModel(String model) =>
    model == 'parakeet_tdt_v3_sherpa' || model == 'qwen3_asr_sherpa';

class SherpaSpeechService {
  Future<NativeSpeechResult> transcribeFile({
    required String audioPath,
    required String model,
    required String modelPath,
    required String locale,
    required double duration,
  }) async {
    final payload =
        await Isolate.run(
          () => _transcribeWithSherpaPayload(
            audioPath: audioPath,
            model: model,
            modelPath: modelPath,
            locale: locale,
            duration: duration,
          ),
        ).whenComplete(() async {
          try {
            await File(audioPath).delete();
          } catch (_) {
            // Temporary recording cleanup is best-effort.
          }
        });
    final error = payload['error'] as String?;
    if (error != null && error.isNotEmpty) {
      throw LocalWhisperException(error);
    }
    return NativeSpeechResult.fromJson(payload);
  }

  void dispose() {}
}

Map<String, Object?> _transcribeWithSherpaPayload({
  required String audioPath,
  required String model,
  required String modelPath,
  required String locale,
  required double duration,
}) {
  try {
    final result = _transcribeWithSherpa(
      audioPath: audioPath,
      model: model,
      modelPath: modelPath,
      locale: locale,
      duration: duration,
    );
    return {
      'transcript': result.transcript,
      'rawTranscript': result.rawTranscript,
      'duration': result.duration,
      'localeId': result.localeId,
      'onDevice': result.onDevice,
      'engine': result.engine,
      'modelId': result.modelId,
      'elapsedMs': result.elapsedMs,
      'rtf': result.rtf,
    };
  } catch (error) {
    return {'error': error.toString()};
  }
}

NativeSpeechResult _transcribeWithSherpa({
  required String audioPath,
  required String model,
  required String modelPath,
  required String locale,
  required double duration,
}) {
  final file = File(audioPath);
  if (!file.existsSync()) {
    throw const LocalWhisperException(
      'Recorded audio file is missing before transcription.',
    );
  }
  if (modelPath.isEmpty || !Directory(modelPath).existsSync()) {
    throw LocalWhisperException(
      'Download ${_displayModelName(model)} before recording.',
    );
  }

  sherpa.initBindings();
  final config = _recognizerConfig(model: model, modelPath: modelPath);
  final recognizer = sherpa.OfflineRecognizer(config);
  final startedAt = DateTime.now();
  try {
    final wave = sherpa.readWave(audioPath);
    if (wave.sampleRate <= 0 || wave.samples.isEmpty) {
      throw const LocalWhisperException(
        'Recorded audio could not be read as WAV.',
      );
    }
    // Qwen3-ASR fits the prompt, the audio, and its answer into a 512-token
    // window. Past ~20 seconds the audio fills it and the answer is cut off
    // after its first word ("language"), so transcribe long recordings in
    // pieces split at pauses.
    final segments = model == 'qwen3_asr_sherpa'
        ? _splitAtPauses(wave.samples, wave.sampleRate)
        : [wave.samples];
    var text = '';
    var lang = '';
    for (final segment in segments) {
      final stream = recognizer.createStream();
      try {
        stream.acceptWaveform(samples: segment, sampleRate: wave.sampleRate);
        recognizer.decode(stream);
        final result = recognizer.getResult(stream);
        text = _joinTranscripts(text, result.text.trim());
        if (lang.isEmpty) lang = result.lang;
      } finally {
        stream.free();
      }
    }
    if (text.isEmpty) {
      throw const LocalWhisperException('No speech was detected.');
    }
    final elapsed = DateTime.now().difference(startedAt);
    return NativeSpeechResult(
      transcript: text,
      rawTranscript: text,
      duration: duration,
      localeId: lang.isNotEmpty ? lang : locale,
      onDevice: true,
      engine: 'sherpa_onnx',
      modelId: model,
      elapsedMs: elapsed.inMilliseconds,
      rtf: duration > 0 ? elapsed.inMilliseconds / 1000 / duration : null,
    );
  } finally {
    recognizer.free();
  }
}

/// Splits [samples] into pieces of at most 12 seconds, cutting each at the
/// quietest 100 ms between 7 seconds and its end so words stay whole. The
/// last piece is kept at least 2 seconds long.
List<Float32List> _splitAtPauses(Float32List samples, int sampleRate) {
  final maxLength = sampleRate * 12;
  final minLength = sampleRate * 7;
  final minTail = sampleRate * 2;
  final frame = sampleRate ~/ 10;
  final pieces = <Float32List>[];
  var start = 0;
  while (samples.length - start > maxLength) {
    final searchEnd = math.min(start + maxLength, samples.length - minTail);
    var cut = searchEnd;
    var quietest = double.infinity;
    for (var f = start + minLength; f + frame <= searchEnd; f += frame ~/ 2) {
      var energy = 0.0;
      for (var i = f; i < f + frame; i++) {
        energy += samples[i] * samples[i];
      }
      if (energy < quietest) {
        quietest = energy;
        cut = f + frame ~/ 2;
      }
    }
    pieces.add(Float32List.sublistView(samples, start, cut));
    start = cut;
  }
  pieces.add(Float32List.sublistView(samples, start));
  return pieces;
}

/// Joins transcript pieces with a space, except between two CJK characters,
/// which are written without one.
String _joinTranscripts(String before, String next) {
  if (before.isEmpty) return next;
  if (next.isEmpty) return before;
  bool isCjk(int rune) =>
      (rune >= 0x3000 && rune <= 0x9FFF) ||
      (rune >= 0xAC00 && rune <= 0xD7AF) ||
      (rune >= 0xF900 && rune <= 0xFAFF) ||
      (rune >= 0xFF00 && rune <= 0xFFEF);
  final joinTight = isCjk(before.runes.last) && isCjk(next.runes.first);
  return joinTight ? '$before$next' : '$before $next';
}

sherpa.OfflineRecognizerConfig _recognizerConfig({
  required String model,
  required String modelPath,
}) {
  return switch (model) {
    'parakeet_tdt_v3_sherpa' => _parakeetConfig(modelPath),
    'qwen3_asr_sherpa' => _qwen3Config(modelPath),
    _ => throw LocalWhisperException(
      '${_displayModelName(model)} is not a Sherpa ONNX transcription pack.',
    ),
  };
}

sherpa.OfflineRecognizerConfig _parakeetConfig(String modelPath) {
  _requireFiles(modelPath, const [
    'encoder.int8.onnx',
    'decoder.int8.onnx',
    'joiner.int8.onnx',
    'tokens.txt',
  ]);
  return sherpa.OfflineRecognizerConfig(
    model: sherpa.OfflineModelConfig(
      transducer: sherpa.OfflineTransducerModelConfig(
        encoder: '$modelPath/encoder.int8.onnx',
        decoder: '$modelPath/decoder.int8.onnx',
        joiner: '$modelPath/joiner.int8.onnx',
      ),
      tokens: '$modelPath/tokens.txt',
      modelType: 'nemo_transducer',
      numThreads: _threadCount(),
      debug: false,
      provider: 'cpu',
    ),
  );
}

sherpa.OfflineRecognizerConfig _qwen3Config(String modelPath) {
  _requireFiles(modelPath, const [
    'conv_frontend.onnx',
    'encoder.int8.onnx',
    'decoder.int8.onnx',
    'tokenizer/merges.txt',
    'tokenizer/vocab.json',
    'tokenizer/tokenizer_config.json',
  ]);
  return sherpa.OfflineRecognizerConfig(
    model: sherpa.OfflineModelConfig(
      qwen3Asr: sherpa.OfflineQwen3AsrModelConfig(
        convFrontend: '$modelPath/conv_frontend.onnx',
        encoder: '$modelPath/encoder.int8.onnx',
        decoder: '$modelPath/decoder.int8.onnx',
        tokenizer: '$modelPath/tokenizer',
        maxNewTokens: 512,
      ),
      tokens: '',
      numThreads: _threadCount(),
      debug: false,
      provider: 'cpu',
    ),
  );
}

void _requireFiles(String modelPath, List<String> files) {
  for (final relative in files) {
    if (!File('$modelPath/$relative').existsSync()) {
      throw LocalWhisperException('Installed model pack is missing $relative.');
    }
  }
}

int _threadCount() {
  final processors = Platform.numberOfProcessors;
  return math.max(1, math.min(4, processors - 1));
}

String _displayModelName(String model) {
  return switch (model) {
    'parakeet_tdt_v3_sherpa' => 'Parakeet-TDT v3',
    'qwen3_asr_sherpa' => 'Qwen3-ASR 0.6B',
    _ => model,
  };
}
