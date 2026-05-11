# Windyomi

Windyomi is a personal fork of [Mangayomi](https://github.com/kodjodevf/mangayomi), rebranded as a Flutter app for reading manga, novels, comics and watching anime across mobile and desktop platforms.

This fork keeps the Mangayomi architecture and extension compatibility, while using its own package name, bundle identifiers, app display name, release links and update metadata.

## Repository

- App name: Windyomi
- Dart package: `windyomi`
- Android/iOS bundle identifier: `com.scanplayext.windyomi`
- URL scheme for Windyomi links: `windyomi://`
- Compatibility URL scheme for tracker OAuth: `mangayomi://`
- GitHub repository: `https://github.com/scanplayext/windyomi`

## Features

- Manga, manhwa, manhua, comics and novel reading
- Anime/video playback support
- Local library and downloads
- Extension support from the Mangayomi ecosystem
- Tracker support for MyAnimeList, AniList, SIMKL, Trakt and Kitsu
- Backups, categories, themes and reader/player settings
- Android, iOS, macOS, Windows and Linux build targets

## Building

Install Flutter and Rust first:

```bash
flutter doctor
rustc --version
```

Install the Flutter Rust Bridge generator:

```bash
cargo install flutter_rust_bridge_codegen
```

Fetch dependencies:

```bash
flutter pub get
```

Run on the current platform:

```bash
flutter run
```

To build iOS you need macOS, Xcode and an Apple signing profile:

```bash
flutter build ipa --release
```

## Releases

GitHub Actions is configured to publish Windyomi artifacts under this repository. The iOS sideloading source at `repo/source.json` is intentionally minimal until the first Windyomi release exists; the source updater workflow will populate release URLs after publishing.

## Attribution

Windyomi is based on Mangayomi by Moustapha Kodjo Amadou and contributors. The original project is licensed under the Apache License 2.0. This fork keeps the original license and copyright notice.

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE).

## Disclaimer

Windyomi does not host content and is not affiliated with third-party content providers or extension sources.
