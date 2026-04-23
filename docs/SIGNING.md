# Code signing & notarization setup

The CI workflow signs both apps with a Developer ID Application certificate and submits them to Apple's notary service, so downloaders can open them with a double-click — no Gatekeeper right-click-Open dance.

This is a **one-time setup** that stores five secrets in the GitHub repo. The CI handles everything after that on every build.

## 1. Create the Developer ID Application certificate

On a Mac signed in to your Apple Developer account:

1. **Xcode → Settings → Accounts**, pick your team.
2. Click **Manage Certificates…**
3. Hit the **+** in the bottom-left and choose **Developer ID Application**.
4. Close the sheet. Xcode has dropped the certificate + private key into your login keychain.

## 2. Export the certificate as a `.p12`

1. Open **Keychain Access**, select the **login** keychain, category **Certificates**.
2. Find the row named `Developer ID Application: <Your Name> (TEAMID)`. Expand it — there should be a private key underneath. (If there isn't, you're on the wrong Mac or the cert was only issued, not installed.)
3. Select both the certificate and the private key (Cmd-click the key).
4. Right-click → **Export 2 items…** → save as `DeveloperID.p12`.
5. Set a strong password when prompted. You'll need this password in step 4.

## 3. Collect your notarization credentials

You need three values:

- **Apple ID** — the email on your developer account.
- **Team ID** — the 10-character identifier (e.g. `ABCDE12345`). Find it at [developer.apple.com/account](https://developer.apple.com/account) under Membership details, or in your certificate's name (`Developer ID Application: Name (TEAMID)`).
- **App-specific password** — generate one at [appleid.apple.com](https://appleid.apple.com) → Sign-In and Security → App-Specific Passwords → Generate. Name it `SwiftTA CI` or similar. It'll look like `abcd-efgh-ijkl-mnop`. Apple won't show it again, so copy it now.

## 4. Add the five GitHub secrets

At `https://github.com/csilvertooth/SwiftTA/settings/secrets/actions`, create these **Repository secrets**:

| Name | Value |
|---|---|
| `MACOS_CERTIFICATE_P12_BASE64` | `base64 -i DeveloperID.p12` (no newlines) |
| `MACOS_CERTIFICATE_PASSWORD` | The password you set in step 2 |
| `MACOS_NOTARIZATION_APPLE_ID` | Your Apple ID email |
| `MACOS_NOTARIZATION_TEAM_ID` | Your 10-character Team ID |
| `MACOS_NOTARIZATION_PASSWORD` | The app-specific password from step 3 |

To get the base64 value on macOS without line wrapping:

```
base64 -i DeveloperID.p12 | pbcopy
```

Paste directly into the secret form.

## 5. Done — the workflow takes over

The next push to `main` will:

1. Import the certificate into a temporary keychain on the runner.
2. Build both apps with `CODE_SIGN_IDENTITY="Developer ID Application"` and `ENABLE_HARDENED_RUNTIME=YES`.
3. Submit each `.app` to `xcrun notarytool` and wait for the ticket.
4. `xcrun stapler staple` the notarization ticket onto the app bundle.
5. Zip and upload both to the `latest` prerelease on the Releases page.

A downloader unzips, drags to `/Applications`, and double-clicks — no prompts.

## Troubleshooting

- **"Code signing is required"** — a secret is missing or empty; the workflow falls back to unsigned builds with a warning in the log.
- **`notarytool` returns `Invalid`** — download the log with `xcrun notarytool log <submission-id>` to see which binary failed. Usually means a bundled dylib isn't signed or hardened runtime is off.
- **Notarization succeeds but `stapler` fails** — the .app's internal structure is wrong (usually nested .framework without a valid Info.plist). Rare for SwiftPM-based apps.
- **Cert expires** — Developer ID Application certs last 5 years. Regenerate in Xcode, re-export, update the `MACOS_CERTIFICATE_P12_BASE64` and `MACOS_CERTIFICATE_PASSWORD` secrets.

## Rotating credentials

- **App-specific passwords**: revoke old ones at [appleid.apple.com](https://appleid.apple.com), generate new, update `MACOS_NOTARIZATION_PASSWORD`.
- **Compromised `.p12`**: revoke the Developer ID cert at [developer.apple.com/account/resources/certificates](https://developer.apple.com/account/resources/certificates) (invalidates existing signed apps!), create a new one, re-export, update both cert secrets.
