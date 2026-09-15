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

The Gemma 3 1B model can ship **inside the APK** so users never download
anything after installing:

1. Accept the license and download
   `Gemma3-1B-IT_multi-prefill-seq_q4_block128_ekv1280.task` (~0.5 GB) from
   [huggingface.co/litert-community/Gemma3-1B-IT](https://huggingface.co/litert-community/Gemma3-1B-IT)
   — one-time, per build machine (the file is license-gated and git-ignored).
2. Drop the file into `assets/models/` (exact name as above — see
   `assets/models/README.md`).
3. Rebuild the APK (`flutter build apk`). On first chat the app auto-installs
   the bundled model — no Hugging Face token, no network.

If the file is missing at build time the APK still builds; the app falls back
to the in-app download flow (Settings → On-device AI → HF token + download).
