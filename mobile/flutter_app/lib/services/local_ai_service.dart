// On-device AI: Gemma 3 1B (int4, ~0.5 GB) runs locally via flutter_gemma.
//
// The model ships BUNDLED inside the APK (assets/models/) when the .task file
// is present at build time — installation happens on-device in seconds on
// first use, with no network access and no Hugging Face token. If the file
// was not bundled into a given build, the service falls back to downloading
// from Hugging Face (license-gated; a free HF token must be saved).
//
// Designed for phones with 4–6 GB RAM: the model is stored in app-private
// storage and loaded into ~1.5–2 GB of RAM at inference time.
//
// All values in the prompt come from the WeatherGPT backend's weather data —
// the on-device model only phrases the answer, it never invents numbers.

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat.dart';

/// Hugging Face repo file: litert-community/Gemma3-1B-IT (int4, 1280 KV cache).
/// Gated behind the (free) Gemma license — needs an HF access token.
const String kLocalModelUrl =
    'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/'
    'Gemma3-1B-IT_multi-prefill-seq_q4_block128_ekv1280.task';

/// Model id used by flutter_gemma's storage layer (file name).
const String kLocalModelId =
    'Gemma3-1B-IT_multi-prefill-seq_q4_block128_ekv1280.task';

/// Where the model ships inside the APK (bundled asset).
///
/// When this asset is present at build time, the model is "installed" from
/// the APK on first use — seconds, offline, no Hugging Face token needed.
/// The .task file is not committed to git (0.5 GB, license-gated); see
/// assets/models/README.md for the one-time manual step per build machine.
const String kLocalModelAssetPath = 'assets/models/$kLocalModelId';

const String kLocalModelLabel = 'Gemma 3 1B (int4) · built into the app';

/// Keys for persisted preferences.
const String _kLocalAiEnabled = 'local_ai_enabled';
const String _kHfToken = 'hf_token';

/// Singleton managing the on-device model lifecycle and inference.
class LocalAiService {
  LocalAiService._();

  static final LocalAiService instance = LocalAiService._();

  InferenceModel? _model;
  bool _initialized = false;

  bool _enabled = false;
  String? _hfToken;

  /// Whether on-device AI is enabled in settings.
  bool get enabled => _enabled;

  /// Current Hugging Face token (used for gated model downloads).
  String? get hfToken => _hfToken;

  /// Whether the model is downloaded and ready for inference.
  bool get isModelReady => _model != null;

  /// True when local inference can be attempted.
  bool get canAnswerLocally => _enabled && _model != null;

  /// Load persisted preferences and initialize the plugin (no model load yet).
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_kLocalAiEnabled) ?? false;
      _hfToken = prefs.getString(_kHfToken);
      // MediaPipe (.task) engine ships inside flutter_gemma 0.12.x —
      // no separate engine registration is needed.
      await FlutterGemma.initialize(huggingFaceToken: _hfToken);
    } catch (e) {
      debugPrint('LocalAiService init failed: $e');
      _initialized = true; // avoid retry loops; allow later re-init via setters
    }
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kLocalAiEnabled, value);
  }

  /// Persist the Hugging Face token and re-initialize the plugin with it.
  Future<void> setHfToken(String? token) async {
    _hfToken = (token == null || token.trim().isEmpty) ? null : token.trim();
    final prefs = await SharedPreferences.getInstance();
    if (_hfToken != null) {
      await prefs.setString(_kHfToken, _hfToken!);
    } else {
      await prefs.remove(_kHfToken);
    }
    // Re-register with the new token so downloads can authenticate.
    await FlutterGemma.initialize(huggingFaceToken: _hfToken);
  }

  /// Whether the model file is present in app storage.
  Future<bool> isModelDownloaded() =>
      FlutterGemma.isModelInstalled(kLocalModelId);

  /// Download the model from Hugging Face (fallback only — used when the
  /// model is not bundled in the APK). Needs a token and license acceptance.
  Future<void> downloadModel(void Function(int progress) onProgress) async {
    await FlutterGemma.installModel(
      modelType: ModelType.gemmaIt,
      fileType: ModelFileType.task,
    ).fromNetwork(kLocalModelUrl, token: _hfToken).withProgress(onProgress).install();
  }

  /// Install the model that ships inside the APK (assets/models/).
  ///
  /// Instant, offline, no token: flutter_gemma copies the bundled .task file
  /// into app storage and marks it active. No-ops when already installed.
  /// Throws if the asset was not bundled into this build (e.g. the .task file
  /// was missing when the APK was built) or the copy fails.
  Future<void> installBundledModel() async {
    await FlutterGemma.installModel(
      modelType: ModelType.gemmaIt,
      fileType: ModelFileType.task,
    ).fromAsset(kLocalModelAssetPath).install();
  }

  /// Make sure the model is available in app storage, then return.
  ///
  /// Order of preference:
  /// 1. Already installed (previous run, or copied from a previous APK).
  /// 2. Bundled in this APK (assets/models/) — installs locally in seconds.
  /// 3. Download from Hugging Face — only when a token has been saved
  ///    (license-gated; requires accepting the Gemma license on HF first).
  Future<void> ensureModelInstalled() async {
    if (await isModelDownloaded()) return;
    try {
      await installBundledModel();
      return;
    } catch (_) {
      // Bundled asset not present in this build — fall through.
    }
    if (_hfToken == null) {
      throw StateError(
        'Model not available in this build and no Hugging Face token saved '
        'for the fallback download.',
      );
    }
    await downloadModel((_) {});
  }

  /// Delete the downloaded model file.
  Future<void> deleteModel() async {
    await closeModel();
    await FlutterGemma.uninstallModel(kLocalModelId);
  }

  /// Load the model into memory (installing it first if needed). Throws if
  /// the model is not installed and cannot be installed.
  Future<void> ensureModelLoaded() async {
    await init();
    if (_model != null) return;
    await ensureModelInstalled();
    _model = await FlutterGemma.getActiveModel(maxTokens: 1024);
  }

  /// Free model memory (call when the app is backgrounded / toggle turned off).
  Future<void> closeModel() async {
    try {
      await _model?.close();
    } catch (_) {}
    _model = null;
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
    final model = _model;
    if (model == null) {
      throw StateError('Local model not loaded');
    }

    final chat = await model.createChat(
      temperature: 0.4,
      topK: 40,
      // Keep replies short — this is a 1B model with a small context window.
      tokenBuffer: 512,
    );

    // System instruction as a model-role prefix, then compact history so
    // short follow-up questions stay coherent.
    await chat.addQueryChunk(Message.text(text: _systemPrompt));
    for (final msg in history.take(4)) {
      await chat.addQueryChunk(
        Message.text(text: _trimForContext(msg.text), isUser: msg.isUser),
      );
    }
    await chat.addQueryChunk(
      Message.text(text: _userPrompt(question, weatherContext), isUser: true),
    );
    final response = await chat.generateChatResponse();
    final text =
        response is TextResponse ? response.token : response.toString();
    final cleaned = _clean(text);
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

  /// Strip stray special tokens the small model may emit.
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
