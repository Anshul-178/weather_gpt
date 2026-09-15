// On-device AI: Gemma 3 1B (GGUF, Q4_K_M, ~769 MB) runs locally via
// llama.cpp through the llama_flutter_android plugin.
//
// The GGUF ships BUNDLED inside the APK (assets/models/) — on first use it is
// stream-copied from the APK assets into app-private storage by native code
// (see MainActivity.copyBundledAsset) and then loaded into RAM by llama.cpp.
// There is no in-app download path and no Hugging Face token anywhere.
//
// Designed for phones with 4–6 GB RAM: Q4_K_M needs ~1 GB for weights plus
// the KV-cache context; Vulkan GPU offload is used when the device supports
// it, with a CPU fallback otherwise.
//
// All values in the prompt come from the WeatherGPT backend's weather data —
// the on-device model only phrases the answer, it never invents numbers.

import 'dart:io' show File;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:llama_flutter_android/llama_flutter_android.dart' as llama;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat.dart';

/// Model file that ships inside the APK (assets/models/).
///
/// When this file is present at build time, the model is "installed" from the
/// APK on first use — no network, no Hugging Face token needed. The .gguf is
/// not committed to git (769 MB, license-gated); see assets/models/README.md
/// for the one-time manual step per build machine.
const String kLocalModelId = 'gemma-3-1b-it-Q4_K_M.gguf';
const String kLocalModelAssetPath = 'assets/models/$kLocalModelId';
const String kLocalModelLabel = 'Gemma 3 1B (GGUF Q4_K_M) · built into the app';

/// Method channel to the native model-file helpers in MainActivity.kt.
/// The native side owns the extracted file's location (filesDir) so the Dart
/// side never has to guess a path.
const MethodChannel _kModelChannel = MethodChannel('weathergpt/local_ai');

/// Keys for persisted preferences.
const String _kLocalAiEnabled = 'local_ai_enabled';

/// Singleton managing the on-device model lifecycle and inference.
class LocalAiService {
  LocalAiService._();

  static final LocalAiService instance = LocalAiService._();

  llama.LlamaController? _controller;
  bool _initialized = false;
  bool _bundledChecked = false;
  String? _extractedPath;

  bool _enabled = false;

  /// Whether on-device AI is enabled in settings.
  bool get enabled => _enabled;

  /// True when the model .gguf was bundled into this APK (build-time fact,
  /// checked once via the asset manifest).
  bool get isModelBundled => _modelBundled;
  bool _modelBundled = false;

  /// Whether the model is loaded and ready for inference.
  bool get isModelReady => _controller != null;

  /// True when local inference can be attempted.
  bool get canAnswerLocally => _enabled && _controller != null;

  /// Load persisted preferences (no model load — that is lazy).
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_kLocalAiEnabled) ?? false;
    } catch (e) {
      debugPrint('LocalAiService init failed: $e');
    }
    if (!_bundledChecked) {
      _bundledChecked = true;
      try {
        final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
        _modelBundled = manifest.listAssets().contains(kLocalModelAssetPath);
      } catch (_) {
        _modelBundled = false;
      }
    }
  }

  /// Path of the extracted model in app storage, or null when it has not
  /// been extracted yet. The native side is the single source of truth.
  Future<String?> _extractedModelPath() async {
    if (_extractedPath != null) return _extractedPath;
    try {
      final path = await _kModelChannel.invokeMethod<String>('modelPath', {
        'targetName': kLocalModelId,
      });
      _extractedPath = path;
    } catch (_) {
      // Channel unavailable (e.g. tests, or platform without the handler).
      return null;
    }
    return _extractedPath;
  }

  /// Whether the GGUF has already been copied into app-private storage.
  Future<bool> isModelExtracted() async =>
      await _extractedModelPath() != null;

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kLocalAiEnabled, value);
  }

  /// Kept for settings-screen compatibility: whether the model file is
  /// present in app storage.
  Future<bool> isModelDownloaded() => isModelExtracted();

  /// Install the model that ships inside the APK (assets/models/).
  ///
  /// Streams the 769 MB asset into app storage via the native method channel
  /// (chunked copy — never loads the file into the Dart heap). Returns the
  /// extracted file's path. No-ops when already extracted. Throws if the
  /// asset was not bundled into this build or the copy fails.
  Future<String> installBundledModel() async {
    final existing = await _extractedModelPath();
    if (existing != null) return existing;
    final path = await _kModelChannel.invokeMethod<String>('copyBundledModel', {
      'assetPath': kLocalModelAssetPath,
      'targetName': kLocalModelId,
    });
    if (path == null || path.isEmpty) {
      throw StateError('Native copy did not return the model path');
    }
    _extractedPath = path;
    return path;
  }

  /// Make sure the model file is available in app storage and return its
  /// path.
  ///
  /// 1. Already extracted (previous run) — nothing to do.
  /// 2. Bundled in this APK (assets/models/) — native chunked copy.
  Future<String> ensureModelInstalled() async {
    final existing = await _extractedModelPath();
    if (existing != null) return existing;
    return installBundledModel();
  }

  /// Delete the extracted model file and free the loaded model.
  Future<void> deleteModel() async {
    await closeModel();
    try {
      final path = await _extractedModelPath();
      if (path != null) {
        final f = File(path);
        if (await f.exists()) await f.delete();
      }
      _extractedPath = null;
    } catch (_) {}
  }

  /// Load the model into memory (extracting it first if needed). Throws if
  /// the model cannot be installed or loaded.
  Future<void> ensureModelLoaded() async {
    await init();
    if (_controller != null) return;
    final modelPath = await ensureModelInstalled();

    final controller = llama.LlamaController();
    try {
      // Vulkan GPU offload when the device supports it; the plugin returns
      // 0 (CPU-only), 16 (partial) or 99 (full offload, clamped natively).
      int gpuLayers = 0;
      try {
        final gpu = await controller.detectGpu();
        gpuLayers = gpu.recommendedGpuLayers;
      } catch (_) {
        // GPU detection failed — fall back to CPU-only inference.
      }
      await controller.loadModel(
        modelPath: modelPath,
        threads: 4,
        // 1B model on 4–6 GB phones: a 2048-token KV cache keeps RAM sane
        // while still fitting system + weather context + short history.
        contextSize: 2048,
        gpuLayers: gpuLayers,
      );
    } catch (e) {
      await controller.dispose();
      rethrow;
    }
    _controller = controller;
  }

  /// Free model memory (call when the app is backgrounded / toggle turned off).
  Future<void> closeModel() async {
    final controller = _controller;
    _controller = null;
    if (controller == null) return;
    try {
      await controller.dispose();
    } catch (_) {}
  }

  /// Ask the on-device model. [weatherContext] is the plain-text weather
  /// summary built from backend data. Throws on any failure so the caller
  /// can fall back to the backend or rule-based answers.
  ///
  /// A fresh chat is built per question with a compact replayed history —
  /// this sidesteps context-window rotation quirks and keeps memory low.
  Future<String> answer(
    String question,
    String weatherContext,
    List<ChatMessage> history,
  ) async {
    await ensureModelLoaded();
    final controller = _controller;
    if (controller == null) {
      throw StateError('Local model not loaded');
    }

    final messages = <llama.ChatMessage>[
      llama.ChatMessage(role: 'system', content: _systemPrompt),
      for (final msg in history.take(4))
        llama.ChatMessage(
          role: msg.isUser ? 'user' : 'assistant',
          content: _trimForContext(msg.text),
        ),
      llama.ChatMessage(
        role: 'user',
        content: _userPrompt(question, weatherContext),
      ),
    ];

    // The plugin auto-detects 'gemma' from the GGUF filename, but be explicit.
    final stream = controller.generateChat(
      messages: messages,
      template: 'gemma',
      temperature: 0.4,
      topK: 40,
      topP: 0.9,
      repeatPenalty: 1.1,
      // Keep replies short — this is a 1B model with a small context window.
      maxTokens: 320,
    );

    final buf = StringBuffer();
    try {
      await for (final token in stream) {
        buf.write(token);
      }
    } finally {
      // Reset the prompt between questions so the 2048-token window is not
      // consumed by earlier turns; history is replayed explicitly instead.
      try {
        await controller.clearContext();
      } catch (_) {}
    }

    final cleaned = _clean(buf.toString());
    if (cleaned.isEmpty) {
      throw StateError('Empty on-device answer');
    }
    return cleaned;
  }

  static const String _systemPrompt =
      'You are WeatherGPT, a friendly weather assistant. Answer ONLY from the '
      'weather data given in the user message — never invent numbers. Keep '
      'answers under 3 sentences, plain text, no lists.';

  static String _userPrompt(String question, String weatherContext) =>
      'Weather data:\n$weatherContext\n\nQuestion: $question\nAnswer briefly:';

  /// History entries are truncated so replay never overflows the window.
  static String _trimForContext(String text) {
    final t = text.trim();
    return t.length <= 220 ? t : '${t.substring(0, 220)}…';
  }

  /// Strip Gemma special tokens the small model may emit.
  static String _clean(String text) {
    var t = text.trim();
    for (final token in [
      '<start_of_turn>',
      '<end_of_turn>',
      '<bos>',
      '<eos>',
    ]) {
      t = t.replaceAll(token, '').trim();
    }
    return t;
  }
}
