# Roost Menu

A small macOS menu bar app for your **Nest thermostats and cameras**. Click the menu bar icon to see the temperature,
change the mode or setpoint, and open live camera views, without opening a browser or phone app.

> Roost Menu is an independent hobby project. It is not affiliated with, endorsed by, or sponsored by Google LLC.
> Google and Nest are trademarks of Google LLC.

## What it does

- **Thermostats:** current temperature, humidity and mode; switch mode, turn Eco on or off, and raise or lower the target
  temperature.
- **Cameras and doorbells:** click to start a live view (WebRTC), expand it into its own resizable window, and watch
  several cameras at once.
- **Your layout:** choose which devices show and put them in the order you like.
- Lives in the menu bar (no Dock icon), shows the current temperature next to the icon, and can launch at login.

It talks to your devices through Google's [Smart Device Management API](https://developers.google.com/nest/device-access)
using **your own** Google project, so nothing passes through anyone else's server.

## "Bring your own keys"

There are no keys built in. Each person creates their own Google Device Access project and pastes three values
into the app's Settings. That takes about **15 minutes and a one-time US$5** fee to Google, and
[SETUP.md](SETUP.md) walks through every click. Without that you can still try the interface with fake devices:

```bash
./run.sh --demo
```

## Requirements

- A Mac with macOS 14 or later (built and tested on Apple silicon).
- A Google account that has your Nest devices in the Google Home app.
- To build from source only: Xcode, and [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

## Download (no Xcode needed)

Releases are signed with a Developer ID and notarized by Apple, so macOS opens them normally. Open the `.dmg`, drag
**Roost Menu** into **Applications**, launch it, and follow [SETUP.md](SETUP.md) to connect your own Google account
(about 15 minutes, one time). macOS may say the app was downloaded from the internet. Click **Open**.

## Build and run from source

```bash
git clone <this repository>
cd <the cloned folder>
./run.sh            # builds, then launches the app
```

By default it builds with a placeholder bundle ID and ad-hoc signing, which is fine for running on your own Mac.
To use your own bundle ID or Apple Developer signing, copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig`
and edit it (that file is git-ignored). Then follow [SETUP.md](SETUP.md) to connect your Google account.

## Privacy

Roost Menu has no server, no analytics and no tracking. Your sign-in token and client secret are stored in your Mac's
Keychain, and the app only talks to Google. Device data and video stay on your Mac. Because everyone runs the app with
their own Google project, there is no central privacy policy: you are the only one who holds your data.

## Known limits

- **Weekly sign-in:** while your Google OAuth app is in *Testing* mode, Google expires the sign-in every 7 days.
  [SETUP.md](SETUP.md) explains how to publish your app to production to stop that. It's optional.
- **"Google hasn't verified this app":** expected for your own project. Click Advanced, then Go to Roost Menu.
- **Battery cameras:** Google only lets streams be extended while a camera is plugged in, so on battery the app starts a
  replacement stream about every five minutes.
- **Not supported by Google's API:** Nest temperature sensors.
- **Tested lightly:** it was built for one household (a thermostat and several cameras) and hasn't been tried widely.
  Expect rough edges, and please don't depend on it for anything critical.

## Disclaimer

Provided as is, with no warranty and no support. You use it at your own risk and are responsible for following Google's
terms for the Device Access program.

## Licence

[MIT](LICENSE)
