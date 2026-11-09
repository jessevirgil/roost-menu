# Roost Menu: one-time Google setup

You need a personal Google account that already has your Nest devices in the Google Home app.
Total time is about 15 minutes. Cost is a one-time $5. This is the exact path that worked.

## 1. Device Access registration ($5)

1. Go to https://console.nest.google.com/device-access and sign in with that Google account.
2. Accept the terms and pay the **US$5** one-time, non-refundable fee.
3. Stop at the empty Projects page. You'll create the project in step 5.

The account is locked to your Device Access project once linked, so use the account that owns your devices.

## 2. Google Cloud project + SDM API

1. Go to https://console.cloud.google.com/projectcreate, name it `Roost Menu`, click **Create**.
2. **Check the project picker at the top.** The console may keep showing an older project. Switch to Roost Menu before continuing.
3. Open https://console.cloud.google.com/apis/library/smartdevicemanagement.googleapis.com?project=YOUR-PROJECT-ID and click **Enable**.
   (YOUR-PROJECT-ID is shown for the project on https://console.cloud.google.com/cloud-resource-manager.)

## 3. OAuth consent screen

1. **Google Auth Platform** → **Get started**.
2. App name `Roost Menu`, your email as support email → **Next**. Audience: **External** → **Next**. Add your email as contact → **Next**.
3. Tick the user-data-policy agreement and click **Create**. Wait for "OAuth configuration created!". Don't reload the page before that, or the form is lost.
4. **Data Access** → **Add or remove scopes** → under "Manually add scopes" paste
   `https://www.googleapis.com/auth/sdm.service` → **Add to table** → **Update** → **Save**.
5. **Audience** → **Test users** → **Add users** → add your own Google account → **Save**.
   Testing mode only lets listed accounts sign in. Skip this and sign-in fails with "Access denied".

## 4. OAuth client

1. **Clients** → **Create client** → Application type **Web application**, name `Roost Menu`.
2. **Authorized redirect URIs** → **Add URI** → exactly `https://www.google.com` → **Create**.
3. Google shows the **Client secret once**. Click its copy icon and paste it straight into the app's Settings.
   If you lose it: client → the **i** panel → **Add secret**, then delete the old one.

## 5. Device Access project

1. At https://console.nest.google.com/device-access click **Create project**.
2. Name `Roost Menu` → **Next** → paste your **Client ID** (ends in `.apps.googleusercontent.com`) → **Next**.
3. Leave **Enable events** off (Pub/Sub is optional and can cost money) → **Create project**.
4. Copy the **Project ID** (a UUID). It is *not* the Cloud project name.

## 6. Build and connect the app

**Build settings (optional).** The app builds as-is with a default bundle ID and ad-hoc signing, which is fine for
running on your own Mac. To use your own bundle ID or an Apple Developer signing identity, copy
`Config/Local.xcconfig.example` to `Config/Local.xcconfig` and edit it. That file is git-ignored. Changing the bundle ID
changes the app's Keychain label and saved settings, so you'd need to re-enter your keys and sign in again after
changing it (pick the ID once and keep it). You need Xcode and `brew install xcodegen`.

1. Run `./run.sh` (or open `build/Build/Products/Debug/RoostMenu.app`). A thermometer appears in the menu bar.
2. Click it → gear. Enter Project ID, Client ID and Client Secret.
3. **Open Google sign-in in my browser**. Pick your account. If you see "Google hasn't verified this app", click
   **Advanced → Go to Roost Menu (unsafe)**. That's expected for your own project. **Tick every device/home** you want to share, then **Allow**.
4. You land on google.com. Copy the **entire address** from the address bar, paste it in the app, **Finish sign-in**.

## The 7-day sign-out (Testing mode)

While the consent screen's publishing status is **Testing**, Google expires the refresh token after **7 days**, so you
repeat step 6.3–6.4 about weekly. Roost Menu tells you when it happens.

This step is optional. If you don't mind signing in weekly, skip it.

The fix is **Audience → Publish app → In production**. That button stays disabled until the **Branding** page has an
application home page, a privacy-policy link and an authorized domain, all verified in Google Search Console.
The author's own pages aren't included here because they carry personal contact details, so you'd write your own:
a home page that says what the app does and links to a privacy policy (say what it accesses, that nothing leaves
your Mac except to Google, and how to sign out or revoke at https://myaccount.google.com/permissions).

What worked without buying a domain (done by the author on 2026-11-08):
1. Put the two pages on a free Netlify site (for example `your-name-roost.netlify.app`) and make sure the site is
   public: Netlify's default login protection must be switched off for it.
2. In https://search.google.com/search-console add a **URL prefix** property for that address and verify it with the
   **HTML file** method (put the `google….html` file next to your pages and redeploy; never delete it).
3. Branding page: fill in the home page and privacy-policy addresses, and add your `….netlify.app` address as an
   authorized domain. Save.
4. Audience → **Publish app** → Confirm. Do **not** submit for verification (not needed for personal use; the app stays
   "unverified", so keep clicking Advanced → Go to Roost Menu at sign-in).
After publishing, sign out and back in once, since tokens issued during Testing keep the 7-day limit.
Free hosts such as `github.io` may not be accepted; Google's own rules say the domain must be one you can verify.

## Making a downloadable build (maintainers)

`tools/release.sh` builds a Developer-ID-signed, notarized `.dmg` in `dist/`. It needs a paid Apple Developer Program
membership and, once per Mac:
1. A **Developer ID Application** certificate (and its private key) in the login Keychain. Xcode > Settings > Accounts >
   Manage Certificates can create it, or create it on developer.apple.com with a certificate request you generate yourself.
2. A saved notarization login: `xcrun notarytool store-credentials "roost-notary" ...` with either an app-specific
   password or an App Store Connect API key.
Then run `DIST_BUNDLE_ID=com.yourname.RoostMenu ./tools/release.sh`. Use a bundle ID that differs from the one in your own
`Config/Local.xcconfig` if you want your personal install and your released build to keep separate settings.

## Using the app

- **Camera:** click to start a live view. Click the expand arrow on the video to open it in its own resizable window
  (mute and keep-on-top buttons inside). Closing that window stops the stream.
- **Several at once:** turn on the two-rectangles icon at the top of the popover. Every camera then opens in its own window.
  Streams left in the popover stop when it closes; streams in their own windows keep going.
- **Choose devices:** show or hide devices and reorder them with the arrows. The order is saved.
- **Thermostat:** mode, Eco and +/- setpoints. Rapid taps are combined into one change.
- The app polls Google every 45 seconds and slows down if Google says it's being rate-limited.
- `./run.sh --demo` runs with fake devices, with no Google account needed.

## Device support notes (checked against Google's Supported Devices page)

- **Nest Doorbell (wired, 2nd gen)**: Google's page lists "Nest Doorbell (wired)", WebRTC only. It doesn't use the "2nd gen" label.
  The app doesn't hard-code models: anything reporting WebRTC live streaming gets a play button.
- **Nest Cam (indoor, wired)** and **Nest Cam (battery)**: supported, WebRTC.
- **Battery cam:** streams can only be extended while plugged in. On battery the app starts a replacement stream every ~5 minutes.
- **Thermostat:** Google says all Nest thermostat models are supported.
- Temperature sensors are not supported by the API.
