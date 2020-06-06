# C19X-iOS

### Decentralised COVID-19 contact tracing.
**Private. Simple. Secure.**

#### PRIVATE
- Anonymous reporting of infection status to help others.
- On-device matching of infection reports to help you.
- Does not collect any personal or location data.

#### SIMPLE
- No registration, no setup, just install and go.
- Two taps to share your infection status.
- App will notify you to review new information.

#### SECURE
- All sensitive on-device data is encrypted (Keychain).
- All network traffic is encrypted (https).
- Bluetooth beacon codes are randomised regularly.

Source code for iOS, Android and Java server are all available for inspection and reuse under MIT License.

This app does not use the Apple - Google Contact Tracing API.

## Features

- Bluetooth beacon
  - Works across iOS (13+) and Android (24+) without software update to latest version.
  - Works well under iOS and Android background mode.
  - Low energy usage and minimal bluetooth data exchange.
- Security
  - HTTPS for all network traffic.
  - AES encrypted message for submitting status updates.
  - Sensitive data encrypted on-device.
- Privacy
  - No user or device data is ever collected.
  - One-time download of shared secret on registration via HTTPS.
  - Published beacon code seeds cannot be traced back to device.

## Building the code

1. Install the latest Xcode developer tools from Apple.
2. Clone the repository.
3. Build and run project.

## Testing the app

1. Install app on two iPhones and place them next to each other.
2. Ensure the iPhones have an internet connection, then start app on both phones.
3. The number of contacts tracked should increase and change regularly, confirming the phones are detecting each other.
4. Change **"How are you today?"** to **"Symptoms"** on one phone, and agree to share the information anonymously.
5. Update will be ready for download after 1 minute on the development server, this will normally be 1 day in production.
6. Double tap **"What you need to do"** on the other phone after 1 minute to request immediate update.
7. **"Recent contacts"** should have changed from **"No report..."** to **"Report of...has been shared"** and **"What you need to do"** should change from **"Stay at home"** to **"Self-isolation"**.

## Preview

![](/Resources/images/AppStore-iPhone-6_5-01.png)
