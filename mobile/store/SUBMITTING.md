# Submitting BorderMe to the App Store

Everything App Store Connect asks for is in this folder, apart from the Developer account. This is the walk from "I have the account" to "it's in review".

1. **Enrol.** Sign up at developer.apple.com/programs ($99 a year) and wait for Apple to approve you. It can take a day or two.

2. **Check signing in Xcode.** Open `mobile/ios/Runner.xcworkspace`. Select each target in turn (**Runner** and **ShareExtension**), go to **Signing & Capabilities**, and confirm your team is chosen, "Automatically manage signing" is on, and **App Groups** lists `group.com.tomlajones.borderme`. The team and the group are already set in the project, so there's probably nothing to tick.
   - With automatic signing, Xcode registers the App IDs (`com.tomlajones.borderme` and `com.tomlajones.borderme.share`) and the group the first time it signs. If it complains, register them by hand at developer.apple.com under Certificates, Identifiers & Profiles, then Identifiers.

3. **Try it on your own iPhone.** Plug it in and run `flutter run --release` from `mobile`. Open Photos, share a picture to BorderMe, and check the Share sheet keeps your last settings. The Share-sheet copies top out at around 3072 px on the long edge; that's iOS limiting extension memory, so don't be surprised.

4. **Create the app in App Store Connect.** Bundle ID `com.tomlajones.borderme`, SKU `borderme-ios`, primary language English (UK).

5. **Build and upload.** A distribution build needs the paid team from step 2, so don't try this before Apple has approved you.
   - Run `cd mobile && flutter build ipa --release`.
   - Every upload needs a new build number. Add `--build-number N` (bump N each time), or change the version in `pubspec.yaml` (`1.0.0+1` means version 1.0.0, build 1).
   - Before uploading, check the Share extension made it into the archive: unzip the `.ipa` and look for `Payload/Runner.app/PlugIns/ShareExtension.appex`.
   - Upload `build/ios/ipa/*.ipa` with Apple's Transporter app, or open the archive in Xcode's Organizer and choose Distribute.

6. **Fill in the listing** from `listing.md`; it has the answers for everything App Store Connect asks.
   - **Screenshots:** upload the three from `store/screenshots` under the 6.9-inch iPhone size (1320 x 2868).
   - **Category and age rating:** Photo & Video, and 4+ (answer "None" throughout the questionnaire).
   - **Content rights:** the app has no third-party content, so answer that it doesn't use any.
   - **Privacy policy URL:** `https://tomlajones.github.io/BorderMe/privacy.html`. It only works once GitHub Pages is switched on for the `docs` folder on `main`, so do that first (Settings, then Pages, then deploy from branch `main`, folder `/docs`) and open the link to check.
   - **App Privacy:** "Data Not Collected".
   - **Export compliance:** already answered "No" through `ITSAppUsesNonExemptEncryption`, so you shouldn't be asked.

7. **Price and availability.** Free, all countries and regions.

8. **Submit for review.** In the review notes, say that there's no login, that the Share extension appears under Share in the Photos app, and that the app only requests add-only photo access.

Then wait, and try not to refresh the page every ten minutes. Good luck.
