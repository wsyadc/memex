# Memex · Photo Journal Edition

[简体中文](README_CN.md)

A simplified fork of [memex-lab/memex](https://github.com/memex-lab/memex) for writing everyday notes, saving photos, and organizing entries with AI. The app interface is Simplified Chinese. Journal files stay on the device, and AI requests use the model service configured by the user.

## Install on Android

Download an APK from [this repository’s Releases](https://github.com/wsyadc/memex/releases) and open it on an Android 8.0 or newer phone.

The preview build uses package `com.memexlab.memex.dev` and launcher name **Memex Dev**. It can coexist with the original app. Export a `.memex` backup from the original app and restore it in the preview to migrate records. The two installations have separate data directories. Future in-place updates must use the same signing key.

## Included features

- Text, camera and gallery capture, with persistent input drafts.
- One photo-and-text journal card, retaining the original input alongside AI-organized content.
- Timeline, calendar browsing, tags and photo viewing.
- Optional location context and file/ZIP import into the journal.
- One configurable default model shared by all remaining AI processing.
- Local storage, manual backup and restore, automatic backups, and developer diagnostics.

Knowledge management, comments, companion characters, insights, long-term memory, voice transcription, AI search, system calendar writes, health collection, photo suggestions, clipboard preview, incoming shares, share posters, custom agents, per-agent model selection, usage statistics, official model accounts and language selection are disabled in the app’s navigation and automatic task registration. Existing workspace files and some compatibility code are retained.

## Reliable capture

The source text and photos are saved before model processing. Each entry gets independent model context and a persisted three-minute processing deadline, shared across retries and restarts. Failed entries retain their saved source and can be processed again. Location and image preparation use bounded waits.

The old queue can make later entries wait behind an unfinished earlier task, including after restart. The new deadline addresses that mechanism; identifying a particular historical service failure still requires its logs.

## Backups

Backups use immutable file snapshots and a consistent SQLite snapshot that includes committed WAL data. Archive checksums come from those same snapshot bytes. Automatic backups run when the app is active and the interval and change conditions are met; the default interval is 24 hours.

Choose a backup folder outside the app and periodically copy backups to another device. A backup on the same phone does not protect against loss of the phone. Backups contain journal content and settings and should be kept private.

## Build

Toolchain: Flutter 3.41.9, Dart 3.11.5, Java 17 and Android NDK 27.0.12077973.

```bash
flutter pub get
flutter run --flavor globalDev
flutter build apk --flavor globalDev --debug
```

The first downloadable build is a development preview. Configure and retain your own signing key for subsequent release builds and updates.

## Attribution and license

Originally developed by [Memex Lab](https://github.com/memex-lab) and contributors. This fork remains licensed under [GPL-3.0](LICENSE), with the original copyright and license notices preserved.
