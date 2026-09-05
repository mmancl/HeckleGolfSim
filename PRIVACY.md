# Privacy Policy for Heckle Golf Simulator

**Last Updated**: September 2026

**Heckle Golf Simulator** ("the Application", "we", "us", or "our") is an open-source, offline-first golf simulation software designed for local golf practice, course play, and entertainment.

We are firmly committed to protecting your privacy. This Privacy Policy explains our data collection, storage, and export practices.

---

## 1. 100% Local Data Storage

- **No Remote Servers**: Heckle Golf Simulator does **not** operate cloud databases, analytics servers, or remote user tracking backends.
- **Local Device Storage**: All user-generated information—including player profiles, golfer names, handicap indexes, custom settings, optional email addresses, swing tempo data, scorecard logs, and ball trajectory statistics—is stored **strictly on your local device** (in the local application data directory).
- **No Third-Party Analytics or Advertising**: The Application contains no third-party tracking SDKs, advertising frameworks, or automated telemetry reporting.

---

## 2. Optional Email & Data Export

The Application includes features that allow players to export their scorecards and shot session statistics (in CSV format) or draft an email summarizing their round:

- **User-Initiated Action Only**: Data is **never** transmitted automatically or silently in the background. Export or email actions only execute when you explicitly click an export or email button.
- **Operating System Default Mail Client**: When an email export is initiated, the Application prepares a local draft file (`.csv` / `.eml`) and asks your operating system to open your preferred default email application (e.g., Apple Mail, Microsoft Outlook, Thunderbird, Gmail, etc.) using standard system URI schemes (`mailto:`).
- **Full User Control**: You retain complete control over whether the email is sent, who receives it, and what content is included. You may review or discard the draft at any time before sending.

---

## 3. Launch Monitor & Hardware Communication

- **Local Network & Bluetooth**: Communications with launch monitors (such as Square Golf via Bluetooth Low Energy or GSPro Open Connect / PiTrac via local TCP socket) occur entirely over your local device interfaces and local area network (LAN).
- **No Off-Device Data Transmission**: Hardware telemetry and ball flight measurements stay on your local machine and are not forwarded to any external servers.

---

## 4. Course Geometry & Geodata

- When loading real-world course geometries, the Application fetches public geographic map vectors (OpenStreetMap) and public elevation tiles (USGS / AWS Open Data).
- These requests do not contain any personal information or player profile data.

---

## 5. Children's Privacy (COPPA & GDPR-K Compliance)

Because Heckle Golf Simulator does not collect, transmit, or store any personal data remotely, it does not collect personal information from children under 13 (or under 16 in the EU/UK).

---

## 6. Open-Source Transparency

Heckle Golf Simulator is open-source software. You can inspect all data handling, storage mechanisms, and network socket code directly in our GitHub repository:
[https://github.com/mmancl/HeckleGolfSim](https://github.com/mmancl/HeckleGolfSim)

---

## 7. Contact Us

If you have questions or concerns regarding this Privacy Policy, please open an issue on our GitHub repository:
[https://github.com/mmancl/HeckleGolfSim/issues](https://github.com/mmancl/HeckleGolfSim/issues)
