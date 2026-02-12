# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Antigravity Player is a desktop video player (Windows/Linux) built with Flutter. It plays local files, network URLs, and streams videos from Telegram via a local HTTP proxy that bridges media_kit/fvp players with TDLib's file download API.

## Common Commands

```bash
# Install dependencies
flutter pub get

# Code generation (required after changing @Riverpod, @freezed, or @TypedGoRoute annotations)
flutter pub run build_runner build --delete-conflicting-outputs

# Code generation in watch mode
flutter pub run build_runner watch

# Run the app
flutter run -d windows
flutter run -d linux

# Run all tests
flutter test

# Run a single test file
flutter test test/infrastructure/services/streaming_lru_cache_test.dart

# Static analysis
flutter analyze

# Build release
flutter build windows --release
flutter build linux --release
```

## Architecture

Clean Architecture with four layers. Dependencies flow inward: Presentation → Application → Domain ← Infrastructure.

### Domain (`lib/domain/`)
Pure Dart, no framework dependencies. Defines `VideoRepository` and `StreamingRepository` interfaces, entities (`VideoEntity`, `PlaylistEntity`), and value objects (`StreamingError`, `LoadingProgress`).

### Application (`lib/application/`)
Use cases orchestrating domain logic: `LoadVideoUseCase`, `SeekVideoUseCase`, `TogglePlaybackUseCase`, `SaveProgressUseCase`, `ClearFinishedProgressUseCase`. All extend `UseCase<Output, Params>`. `StorageKeyService` generates stable persistence keys prioritizing Telegram message IDs over file IDs over file paths.

### Infrastructure (`lib/infrastructure/`)
Two video backends implementing `VideoRepository`:
- `MediaKitVideoRepository` — primary, uses media_kit (libmpv)
- `FvpVideoRepository` — alternative, uses fvp (libvlc)

The **Local Streaming Proxy** (`LocalStreamingProxy`) is the most complex component. It's a singleton HTTP server on 127.0.0.1 that converts Range requests into TDLib file downloads. Key subsystems:
- `ProxyFileState` — per-file state machine: idle → loadingMoov → moovReady → seeking → playing
- `StreamingLRUCache` — 32MB per-file backward seek cache with 512KB chunks
- `DownloadMetrics` — speed tracking and stall detection (<50KB/s for >2s)
- `ProxyConfig` — centralized configuration constants
- `DownloadPriority` — user seeks (32) > active playback (16) > visible preload (5) > background (1)
- `MP4SampleTable` — parses MOOV atom for accurate byte-offset seeking
- `RetryTracker` — per-file retry counting

Proxy URL format: `http://127.0.0.1:{port}/stream?file_id={id}&size={bytes}`

`TelegramService` wraps TDLib via FFI for auth and file operations. `SecureStorageService` handles encrypted credential storage.

### Presentation (`lib/presentation/`)
State management via **Riverpod 3.0** with code generation. Key providers:
- `PlayerBackend` — selects media_kit or fvp
- `videoRepositoryProvider` — provides the active `VideoRepository`
- `streamingRepositoryProvider` — provides `StreamingRepository`
- `PlayerNotifier` (the main controller) — manages `PlayerState` (Freezed), subscribes to 6 streams (position, duration, isPlaying, isBuffering, tracksChanged, error), handles auto-save every 5s

Navigation via **GoRouter** with type-safe code-generated routes (`@TypedGoRoute` in `routes.dart`). Route extras use a custom codec for complex parameters.

## Code Generation

Three generators produce `*.g.dart` and `*.freezed.dart` files:
1. **riverpod_generator** — `@Riverpod` annotations → provider boilerplate
2. **freezed** — `@freezed` annotations → immutable data classes with copyWith/equality
3. **go_router_builder** — `@TypedGoRoute` annotations → type-safe route classes

Generated files are checked in. After modifying annotated classes, run `build_runner build`.

## Key Patterns

- **Position throttling**: Player position updates every 200ms (`AppConstants.positionUpdateInterval`) to prevent CPU overhead
- **MOOV atom handling**: Proxy detects MP4 files with metadata at end-of-file, loads MOOV first before seeking
- **Error classification**: `PlayerNotifier._classifyPlayerError` maps player error strings to `StreamingError` types (unsupportedCodec, corruptFile). Files marked `FileLoadState.unsupported` get 503 responses, preventing retry loops
- **Zombie protection**: Proxy detects stale HTTP connections from old seeks and prevents them from hijacking active downloads
- **Progress persistence**: Uses stable storage keys (`telegram_{chatId}_{messageId}` > `file_{fileId}` > path) so playback position survives cache clears

## Platform Notes

- **Windows**: Primary target. Custom title bar via `window_manager` with `TitleBarStyle.hidden`
- **Linux**: Full support. Uses `exit(0)` on window close to avoid OpenGL shader cleanup warnings. Integrates D-Bus MPRIS via `mpris_service`
- **Mobile**: Not targeted (desktop only)

## Environment

Requires a `.env` file (see `.env.example`) loaded via `flutter_dotenv` at startup. Contains Telegram API credentials and TDLib configuration.

## Language

Code comments and UI strings are in Spanish. Commit messages are also in Spanish.
