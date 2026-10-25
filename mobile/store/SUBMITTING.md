# Submitting BorderMe to the App Store

Everything App Store Connect asks for is in this folder, apart from the Developer account. This is the walk from "I have the account" to "it's in review".

1. **Enrol.** Sign up at developer.apple.com/programs ($99 a year) and wait for Apple to approve you. It can take a day or two.

2. **Set up signing in Xcode.** Open `mobile/ios/Runner.xcworkspace` (use `Runner.xcodeproj` if there's no workspace).
   - For both the **Runner** and **ShareExtension** targets, open **Signing & Capabilities**, choose your team and leave "Automatically manage signing" on.
   - Under **App Groups**, tick `group.com.tomlajones.borderme` for both targets. Xcode registers it for you.

3. **Try it on your own iPhone.** Plug it in and run `flutter run --release` from `mobile`. Open Photos, share a picture to BorderMe, and check the Share sheet keeps your last settings. The Share-sheet copies top out at around 3072 px on the long edge; that's iOS limiting extension memory, so don't be surprised.

4. **Create the app in App Store Connect.** Bundle ID `com.tomlajones.borderme`, SKU `borderme-ios`, primary language English (UK).

5. **Build and upload.**
   - Run `cd mobile && flutter build ipa --release`.
   - Upload `build/ios/ipa/*.ipa` with Apple's Transporter app, or open the archive in Xcode's Organizer and choose Distribute.

6. **Fill in the listing** from `listing.md`, and add the screenshots from `store/screenshots`. They're 1320 x 2868, the iPhone 6.9-inch size.
   - **Privacy policy URL:** `https://tomlajones.github.io/BorderMe/privacy.html`. It only works once GitHub Pages is switched on for the `docs` folder on `main`, so do that first (Settings, then Pages, then deploy from branch `main`, folder `/docs`) and open the link to check.
   - **App Privacy:** "Data Not Collected".
   - **Export compliance:** already answered "No" through `ITSAppUsesNonExemptEncryption`, so you shouldn't be asked.

7. **Price and availability.** Free, all countries and regions.

8. **Submit for review.** In the review notes, say that there's no login, that the Share extension appears under Share in the Photos app, and that the app only requests add-only photo access.

Then wait, and try not to refresh the page every ten minutes. Good luck.
