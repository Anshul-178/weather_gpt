# Bundled on-device AI model

Drop the Gemma model file here before building the release APK:

```
Gemma3-1B-IT_multi-prefill-seq_q4_block128_ekv1280.task   (~0.5 GB)
```

The app auto-installs it from this folder on first use — no in-app download
and no Hugging Face token is needed at runtime.

## One-time manual step (license-gated file)

The file cannot be committed here (0.5 GB) and is license-gated on
Hugging Face, so fetch it once yourself:

1. Sign in at https://huggingface.co/litert-community/Gemma3-1B-IT and
   accept the (free) Gemma license.
2. Download `Gemma3-1B-IT_multi-prefill-seq_q4_block128_ekv1280.task`
   (or use a read token with curl/huggingface-cli).
3. Place the file in this folder, keeping the exact file name — the app
   looks for `Gemma3-1B-IT_multi-prefill-seq_q4_block128_ekv1280.task`.

## Build notes

- The file is git-ignored (see `.gitignore`) — it never enters version
  control; each build machine needs its own copy.
- `flutter pub get` and a full rebuild are needed after adding the file so
  the asset bundle picks it up.
- If the file is missing at build time, the APK still builds: the app
  falls back to the in-app download flow (Settings → On-device AI).
