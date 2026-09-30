# Install Ritme

Ritme's development releases follow the same distribution approach as TallyDex: an unsigned iPhone IPA and a source feed for compatible sideloading apps.

**Requires iOS 26 or later.** This is a development beta, not an App Store or AltStore PAL release.

## AltStore source

Add this URL in the Sources section of AltStore Classic, SideStore, FlareStore, or another compatible installer:

```text
https://raw.githubusercontent.com/MiranoVerhoef/Ritme/main/altstore-source.json
```

Choose **Ritme** from the source and install it. Availability of third-party sources depends on your installer and version. The feed includes the exact version, build, IPA byte count, minimum iOS version, screenshots, and location permission descriptions.

Alternatively, download `Ritme-v0.1.2.ipa` from the [GitHub release](https://github.com/MiranoVerhoef/Ritme/releases/tag/v0.1.2), then import it into your sideloading app. The IPA is unsigned; your installer must sign it for your iPhone. With a free Apple account, AltStore Classic installations normally expire after seven days and require refreshing. See the [official AltStore Classic guide](https://faq.altstore.io/altstore-classic/your-altstore) for signing, refresh, and account limits.

## What this package includes

- Native iPhone interface, manual and GPS trips, route maps, saved places, Work/Private marking, work schedules and holiday mode.
- CSV, PDF and GPX exports.
- Guided Shortcuts setup for CarPlay and Bluetooth start/end triggers. You create the personal automations yourself; start/end actions open Ritme in this beta.
- Local storage. iCloud sync is **not active** in the distributed build.

Allow location access to record a trip. Background access is needed to continue an active trip with the phone locked. Test recording and Shortcuts on your own iPhone before relying on mileage records; battery usage and real driving accuracy have not yet been validated.

## Apple Watch

The repository includes a Watch companion with Work/Private controls. The sideload IPA intentionally omits it because Watch signing and installation through sideloaders have not been verified. Install both targets through Xcode with your developer team to test the companion on a paired Watch (watchOS 11 or later). Paired-device delivery still needs physical testing.

## Build a new release

From the repository root on a Mac with Xcode 27:

```sh
xcodebuild -project Ritme.xcodeproj -scheme Ritme -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build/ReleaseDerivedData \
  CODE_SIGNING_ALLOWED=NO build
python3 Scripts/package_release.py
python3 Scripts/generate_altstore_source.py build/releases/Ritme-v0.1.2.ipa --date 2026-09-30
```

Update the version/build in the iPhone and Watch Info.plists before a new version. Use that version's IPA filename and release date in the feed command. The packaging script checks the device platform, copies the unsigned build, and removes Watch content only from the distribution copy. Upload the IPA to the matching GitHub release; keep the source feed's download URL and file size consistent with the uploaded asset. Preserve previous version entries when adding future releases.

The feed format follows [AltStore's official source documentation](https://faq.altstore.io/developers/make-a-source).
