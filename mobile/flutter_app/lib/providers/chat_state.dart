import 'package:flutter/foundation.dart';

import '../models/chat.dart';
import '../providers/app_state.dart';
import '../repositories/weather_repository.dart';
import '../services/api_service.dart';
import '../services/local_ai_service.dart';
import '../services/voice_service.dart';
import '../services/weather_context_builder.dart';

/// Chat state: message list + conversation continuity.
///
/// When on-device AI is enabled and the Gemma model is ready, questions are
/// answered locally (works offline, private, no server round-trip). Anything
/// the local model can't handle falls back to the WeatherGPT backend.
class ChatState extends ChangeNotifier {
  final WeatherRepository _repository = WeatherRepository();
  final AppState appState;

  /// True when the last answer came from the on-device model.
  bool lastAnswerWasLocal = false;

  ChatState(this.appState) {
    ApiService.instance.isRetrying.addListener(_onRetryingChanged);
    _loadLocalState();
  }

  Future<void> _loadLocalState() async {
    await LocalAiService.instance.init();
    lastAnswerWasLocal = false;
    notifyListeners();
  }

  void _onRetryingChanged() {
    notifyListeners();
  }

  @override
  void dispose() {
    ApiService.instance.isRetrying.removeListener(_onRetryingChanged);
    super.dispose();
  }

  final List<ChatMessage> messages = [
    ChatMessage(
      text: 'Hi! Ask me anything about the weather — rain, temperature, '
          'what to wear, or whether it\'s a good day for cricket.',
      isUser: false,
      time: DateTime.now(),
    ),
  ];

  bool sending = false;
  bool autoSpeak = true;
  String voiceLanguage = 'auto'; // Detect response language from each message.

  static const List<String> suggestedQuestions = [
    'Will it rain today?',
    'What should I wear today?',
    'क्या आज बारिश होगी?',
    'Is tomorrow good for cycling?',
  ];

  void setAutoSpeak(bool value) {
    autoSpeak = value;
    notifyListeners();
  }

  void setVoiceLanguage(String lang) {
    voiceLanguage = lang;
    // Keep the voice service in sync so TTS uses the same language.
    VoiceService.instance.language = lang;
    notifyListeners();
  }

  /// Attempt an on-device answer; returns null when local AI can't be used.
  Future<String?> _tryLocalAnswer(String question) async {
    final local = LocalAiService.instance;
    if (!local.canAnswerLocally) return null;
    final current = appState.current;
    if (current == null && appState.hourly.isEmpty && appState.daily.isEmpty) {
      // No weather data on the device yet — let the backend answer.
      return null;
    }
    try {
      final context = buildWeatherContext(
        current,
        appState.hourly,
        appState.daily,
        appState.location?.name,
      );
      // Last few messages as lightweight context for follow-ups.
      final history = messages
          .where((m) => !m.isError)
          .toList()
          .reversed
          .take(4)
          .toList()
          .reversed
          .toList();
      final answer = await local.answer(question, context, history);
      lastAnswerWasLocal = true;
      return answer;
    } catch (e) {
      debugPrint('Local AI failed, falling back to backend: $e');
      lastAnswerWasLocal = false;
      return null;
    }
  }

  Future<void> send(String text, {bool? speakResponse}) async {
    final question = text.trim();
    if (question.isEmpty || sending) return;
    if (appState.location == null) {
      messages.add(ChatMessage(
        text: 'Please pick a location first.',
        isUser: false,
        time: DateTime.now(),
        isError: true,
      ));
      notifyListeners();
      return;
    }

    messages.add(ChatMessage(
      text: question,
      isUser: true,
      time: DateTime.now(),
    ));
    sending = true;
    lastAnswerWasLocal = false;
    notifyListeners();

    try {
      // 1) On-device model (if enabled + ready): fast, private, offline.
      final localAnswer = await _tryLocalAnswer(question);
      if (localAnswer != null) {
        messages.add(ChatMessage(
          text: localAnswer,
          isUser: false,
          time: DateTime.now(),
        ));
        if (speakResponse ?? autoSpeak) {
          await _speakAnswer(localAnswer);
        }
        sending = false;
        notifyListeners();
        return;
      }

      // 2) WeatherGPT backend (LLM + rule-based fallback server-side).
      final answer = await _repository.sendChat(
        question,
        appState.location!.latitude,
        appState.location!.longitude,
        appState.conversationId,          locationName: appState.location!.name,
      );

      appState.conversationId =
          (answer['conversation_id'] as num?)?.toInt() ?? appState.conversationId;
      final answerText = answer['answer'] as String? ?? '…';
      final timestamp = answer['timestamp'];
      final msgTime = timestamp != null
          ? DateTime.tryParse(timestamp as String) ?? DateTime.now()
          : DateTime.now();
      messages.add(ChatMessage(
        text: answerText,
        isUser: false,
        time: msgTime,
      ));

      if (speakResponse ?? autoSpeak) {
        // Automatically speak using VoiceService
        await _speakAnswer(answerText);
      }
    } on ApiException catch (e) {
      messages.add(ChatMessage(
        text: e.message,
        isUser: false,
        time: DateTime.now(),
        isError: true,
      ));
    } catch (e) {
      messages.add(ChatMessage(
        text: 'Could not reach the WeatherGPT server. Please try again.\n\nDebug: $e',
        isUser: false,
        time: DateTime.now(),
        isError: true,
      ));
    }
    sending = false;
    notifyListeners();
  }

  Future<void> _speakAnswer(String text) async {
    try {
      final voice = VoiceService.instance;
      await voice.speak(text);
    } catch (_) {}
  }
}
