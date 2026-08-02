# Google Play release

**Not ready to publish.** The campaign is incomplete — see
`docs/known_limitations.md` §1. This document records the configuration that is
in place and the steps that remain.

---

## Configuration in place

| Setting | Value |
| --- | --- |
| App name | Chain Reaction City |
| Flutter project name | `chain_reaction_city` |
| Application ID | `ae.kanbanstudios.chainreactioncity` |
| Version | `1.0.0+1` (from `pubspec.yaml`) |
| Min SDK | 24 (Android 7.0) |
| Target SDK | Flutter default for 3.44.8 |
| Orientation | Portrait only, locked in the manifest and at runtime |
| Icon | Adaptive (foreground + `#F2F2F3` background) + legacy + round, all from `logo.png` |
| Splash | `logo.png` on the studio background |
| Permissions | `VIBRATE` only |
| Minify / shrink resources | On, with ProGuard keep rules for the Flutter embedding |
| AAB splits | Language off, density and ABI on |

The app is **fully offline**: no network permission, no analytics, no ads, no
third-party SDKs. The shop sells cosmetics for coins earned by playing; there
are no real-money purchases, so no billing library is integrated and there is
nothing to restore.

---

## Signing — the one blocking step

`android/app/build.gradle.kts` reads an upload keystore from
`android/key.properties` when it exists and **falls back to the debug keystore
when it does not**. No `key.properties` is committed, so the APK and AAB built
in this repository are **debug-signed and cannot be uploaded to Play**.

To produce an uploadable build:

```bash
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Then create `android/key.properties` — git-ignored, never committed:

```properties
storePassword=<password>
keyPassword=<password>
keyAlias=upload
storeFile=<absolute path to upload-keystore.jks>
```

Then:

```bash
flutter build appbundle --release
```

Verify before uploading:

```bash
jarsigner -verify -verbose -certs build/app/outputs/bundle/release/app-release.aab
```

Keep the keystore and its passwords in a password manager. Losing the upload key
means enrolling in Play App Signing key reset, which is slow.

---

## Build commands

```bash
flutter build apk --debug
```

```bash
flutter build apk --release
```

```bash
flutter build appbundle --release
```

Outputs:

| Artefact | Path | Size |
| --- | --- | --- |
| Debug APK | `build/app/outputs/flutter-apk/app-debug.apk` | 150.0 MB |
| Release APK | `build/app/outputs/flutter-apk/app-release.apk` | 49.8 MB |
| Release AAB | `build/app/outputs/bundle/release/app-release.aab` | 49.5 MB |

Upload the **AAB**. Play splits it per ABI and density, so the real download is
much closer to the 21.6 MB single-ABI APK than to the 49.5 MB bundle.

---

## Store listing

Fill these in when the campaign is finished.

- **Title:** Chain Reaction City
- **Short description:** One tap. Total chaos.
- **Category:** Games → Puzzle
- **Content rating:** expected Everyone / PEGI 3 — no violence, no chat, no
  user-generated content, no purchases
- **Target audience:** general; the game has no ads and no data collection, so
  the Families policy surface is small, but the questionnaire still needs
  completing
- **Graphics:** feature graphic and screenshots not produced

### Data safety

The declaration is short and should be filled in as:

- **Data collected:** none
- **Data shared:** none
- **Data encrypted in transit:** not applicable — the app makes no network calls
- **Data deletion:** all progress is local; Settings → Reset all progress clears it

There is no privacy policy document in this repository. Play requires a hosted
URL even for an app that collects nothing.

---

## Pre-launch checklist

Ordered by what blocks what.

- [ ] **Finish the campaign** — 50 completable levels (`docs/known_limitations.md` §1)
- [ ] `flutter test` green, including `campaign_test.dart`
- [ ] Write the integration tests the brief specifies
- [ ] Test on a physical mid-range device; re-measure performance
- [ ] Listen to the audio mix
- [ ] Verify every meta screen on device (map, shop, city, daily, lab, settings)
- [ ] Create the upload keystore and `android/key.properties`
- [ ] Confirm the release build is upload-signed
- [ ] Host a privacy policy and complete Data Safety
- [ ] Produce screenshots and the feature graphic
- [ ] Internal testing track first, then closed, then production

---

## Versioning

`pubspec.yaml`'s `version: 1.0.0+1` drives both `versionName` and
`versionCode`. Bump the `+N` build number on every upload — Play rejects a
duplicate `versionCode`.
