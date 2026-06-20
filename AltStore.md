# Plan: Install Smartponic V2 on iPhone Using a Windows Laptop

This plan outlines the process of building this Flutter iOS application in the cloud using [Codemagic](https://codemagic.io) and sideloading it onto a physical iPhone using AltStore on a Windows environment.

**Your project details (for reference):**
- App name: `Smartponic V2`
- Bundle ID: `com.example.smartponicV2`
- Git branch with your changes: `dev-optimization`
- iOS code signing style: Automatic

---

## Phase 0: Prepare Your Code for iOS

> ⚠️ **Do this FIRST before the build step.**

- [ ] **Commit or stash your local changes** — Codemagic builds from the remote repo, so local uncommitted changes won't be included:
  ```bash
  git add -A
  git commit -m "prep for iOS testing build"
  git push origin dev-optimization
  ```
- [ ] Alternatively, create a dedicated branch for iOS testing:
  ```bash
  git checkout -b ios-testing
  git push origin ios-testing
  ```

---

## Phase 1: Prerequisites

- [ ] Enable **Developer Mode** on your iPhone via **Settings > Privacy & Security > Developer Mode**, then restart.
- [ ] Ensure you have an Apple ID ready (a free one works for 7-day testing).
- [ ] If your Apple ID has **2FA enabled** (likely), generate an **App-Specific Password**:
  1. Go to [appleid.apple.com](https://appleid.apple.com) and sign in.
  2. Navigate to **App-Specific Passwords** → **Generate**.
  3. Copy the password (it looks like `xxxx-xxxx-xxxx-xxxx`).
  4. You'll use this instead of your normal password during AltStore provisioning.

---

## Phase 2: Cloud Build Configuration (Codemagic)

Codemagic has a free tier with 500 build minutes/month — more than enough for testing.

- [ ] Create a [Codemagic](https://codemagic.io) account using your GitHub credentials.
- [ ] Click **Add application** and select your remote repository (`hyelif/SmartPonic-Optimization` or `hyelif/Flutter-Apps-Development`).
- [ ] In **Workflow settings**, disable Android and enable **iOS** builds.
- [ ] Configure the **Build** tab options:
  - **Flutter version** — select the latest stable (matching `^3.11.3` SDK requirement).
  - **Xcode version** — latest stable.
  - **Build mode** → **Debug** (required — AltStore can only resign debug builds).
  - **iOS code signing** → set **Export method** to **Development** with **Automatic signing**.
- [ ] Set the **Branch** to `dev-optimization` (or your testing branch).
- [ ] Click **Start New Build** and wait (~5–10 minutes).
- [ ] Once complete, **download** the generated `runner.app.zip` (or if you set up code signing properly, a `.ipa` file directly).

> 💡 **Tip:** If Codemagic produces a `.ipa` directly (happens when export method is set correctly), you can skip Phase 3 entirely and jump straight to Phase 4.

---

## Phase 3: Binary Packaging on Windows

Only needed if Codemagic gave you a `.zip` instead of an `.ipa`.

- [ ] Extract the downloaded `runner.app.zip`.
- [ ] Locate the `Runner.app` folder. If you find an `.xcarchive` instead, dig deeper:
  ```
  Runner.xcarchive/Products/Applications/Runner.app
  ```
- [ ] Create a new directory named exactly `Payload` (case-sensitive).
- [ ] Move/copy `Runner.app` **into** the `Payload` folder.
- [ ] Compress the `Payload` folder into a `.zip` file (right-click → **Compress**).
- [ ] Rename the resulting file from `Payload.zip` → `SmartponicV2.ipa`.

---

## Phase 4: Device Sideloading (AltStore)

- [ ] Download and install **iTunes** and **iCloud** directly from [Apple's website](https://www.apple.com/itunes/) — **do NOT use the Microsoft Store versions**, as those lack Bonjour and other components AltServer needs.
- [ ] Sign in to **iCloud for Windows** with the same Apple ID you'll use for AltStore provisioning.
- [ ] Download and install [**AltServer for Windows**](https://altstore.io/).
- [ ] Connect your iPhone via USB, and select **Trust This Computer** on the device.
- [ ] **Ensure Wi-Fi is ON on the iPhone** — AltStore needs it even over USB.
- [ ] In the Windows system tray, find the **AltServer** icon (diamond-shaped), click it → **Install AltStore** → select your iPhone.
- [ ] When prompted, enter your Apple ID credentials:
  - **Email:** your Apple ID
  - **Password:** the **App-Specific Password** you generated in Phase 1 (not your normal password if 2FA is on).
- [ ] On the iPhone, go to **Settings > General > VPN & Device Management** (or just **Device Management** on newer iOS) and **trust** the Apple ID profile.
- [ ] Open the **AltStore** app on your iPhone → tap the **+** icon → select `SmartponicV2.ipa` → tap **Install**.

---

## Phase 5: Ongoing Maintenance ⚠️

> **This is the part most guides forget — and why your app will stop working after 7 days.**

Free Apple Developer profiles expire every **7 days**. You must refresh before then:

- [ ] Set a recurring **calendar reminder for day 6** to refresh.
- [ ] On refresh day:
  1. Connect iPhone to your Windows laptop (or same Wi-Fi with AltServer running).
  2. Open **AltStore** on the iPhone.
  3. Tap **Refresh All**.
  4. Enter your App-Specific Password again if prompted.
- [ ] The app will continue working for another 7 days. Repeat indefinitely.

---

## Troubleshooting

| Problem | Likely Fix |
|---------|-----------|
| AltServer says "Cannot find iPhone" | Reinstall iTunes (non-Microsoft Store), restart AltServer, reconnect USB |
| Installation fails with error | Ensure iCloud is signed in with the same Apple ID used in AltServer |
| App crashes on launch | Rebuild with Codemagic in **Debug** mode (Release builds can't be resigned by AltStore) |
| "Untrusted Developer" on iPhone | Go to **Settings > General > VPN & Device Management** and trust the profile |
| 7-day expiry warning | Refresh in AltStore (Phase 5) — don't delete the app or you'll lose its data |

---

## Future: App Store Distribution

When you're ready for real distribution (no 7-day limit, no USB tethering):
1. [ ] Join the [Apple Developer Program](https://developer.apple.com/) ($99/year).
2. [ ] Change the bundle ID from `com.example.smartponicV2` to something unique.
3. [ ] Set up production certificates in Codemagic.
4. [ ] Build in **Release** mode and submit via App Store Connect.