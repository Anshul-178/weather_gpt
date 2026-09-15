# weathergpt (Flutter client)

AI-powered weather assistant for Android — WeatherGPT.

## Getting Started

```bash
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

`10.0.2.2` is the Android-emulator alias for your host machine. For a physical
device use your PC's LAN IP. Without `--dart-define` the app uses the deployed
Render backend (see `lib/config.dart`). The backend URL can also be changed at
runtime in **Settings → Backend URL**.

## Bundled on-device AI model (no in-app download)

The Gemma 3 1B GGUF ships **inside the APK** and runs on-device via
**llama.cpp** (`llama_flutter_android`) — users never download anything after
installing and no Hugging Face token exists in the app:

1. Accept the license and download `gemma-3-1b-it-Q4_K_M.gguf` (~769 MB) from
   [huggingface.co/litert-community/Gemma3-1B-IT](https://huggingface.co/litert-community/Gemma3-1B-IT)
   — one-time, per build machine (the file is license-gated and git-ignored).
2. Drop the file into `assets/models/` (exact name as above — see
   `assets/models/README.md`, or run `./tools/fetch_model.sh hf_YOUR_TOKEN`).
3. Rebuild the APK (`flutter build apk`). On first chat the app copies the
   model from the APK into app storage (seconds) and llama.cpp loads it —
   Vulkan GPU offload is used when the device supports it.

If the file is missing at build time the APK still builds; on-device AI
reports that the model is not included and chat uses the WeatherGPT backend.

Requirements: Android 8.0+ (minSdk 26), ~1.5 GB free RAM while the model is
loaded.
