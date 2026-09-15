# Bundled on-device AI model

Drop the Gemma GGUF model file here before building the release APK:

```
gemma-3-1b-it-Q4_K_M.gguf   (~769 MB)
```

The app runs it on-device with **llama.cpp** (via `llama_flutter_android`) and
auto-installs it from this folder on first use — no in-app download and no
Hugging Face token is needed at runtime.

## One-time manual step (license-gated file)

The file cannot be committed here (769 MB) and Gemma is license-gated on
Hugging Face, so fetch it once yourself:

1. Sign in at https://huggingface.co/litert-community/Gemma3-1B-IT and
   accept the (free) Gemma license.
2. Fetch the GGUF with the helper script (needs a read token):

   ```
   cd mobile/flutter_app
   ./tools/fetch_model.sh hf_YOUR_TOKEN
   ```

   or download `gemma-3-1b-it-Q4_K_M.gguf` manually from the model page
   (Files → `*Q4_K_M*.gguf`).
3. Place the file in this folder, keeping the exact file name — the app
   looks for `gemma-3-1b-it-Q4_K_M.gguf` and only wires the llama.cpp engine
   when this exact file is present.

## How it works at runtime

- The GGUF is bundled into the APK as a Flutter asset.
- On first chat the native side (`MainActivity.copyBundledAsset`) streams it
  out of the APK into app-private storage in 1 MiB chunks (never loaded into
  the Dart heap).
- llama.cpp loads it into RAM (~1 GB weights + ~0.3 GB KV cache at 2048
  context) with Vulkan GPU offload when the device supports it, CPU otherwise.
- Deleting the model in Settings removes the extracted copy; it is
  re-copied from the APK on next use.

## Build notes

- The file is git-ignored (see `.gitignore`) — it never enters version
  control; each build machine needs its own copy.
- `flutter pub get` and a full rebuild are needed after adding the file so
  the asset bundle picks it up.
- If the file is missing at build time, the APK still builds: on-device AI
  reports that the model is not included and chat uses the WeatherGPT
  backend. (The old `.task` fallback download was removed together with the
  MediaPipe engine.)
