# Dynamic Island for Mac

The iPhone's Dynamic Island, living in your MacBook's notch. It sits over the
notch when nothing is going on, grows out of it when something happens, and
gets out of the way again.

Free and open source. Needs macOS 14 Sonoma or later. Made for MacBooks with a
notch; on other displays it draws its own.

## What it does

- **Now Playing** – album art on one side of the notch, a waveform in the art's
  colour on the other. Hover for the full player with a scrubbable progress
  bar, play/pause and next/previous. Works with Apple Music, Spotify, YouTube in
  any browser, Podcasts – anything that shows up in Control Center.
- **Timer** – start one from the island or the menu bar. With music playing
  as well, the island shows both: album art on the left, the countdown on the
  right.
- **Charging** – while the Mac charges, the island shows the power coming in
  and the time until full. Music and the timer take priority.
- **Alerts** – charging, low battery (20%, 10%, 5%), volume and brightness
  changes, and Bluetooth devices connecting or disconnecting (AirPods,
  keyboards, mice).

Hover or click the notch to open it. Right-click it for settings.

It's light on resources: 0% CPU and around 15–20 MB of memory when idle. The
waveform and scrolling song titles are animated by Core Animation, so the app
does no per-frame work even while music is playing.

## Install

1. Download `DynamicIsland.zip` from
   [Releases](https://github.com/Achitsak/dynamic-island-mac/releases/latest),
   unzip it and move **Dynamic Island.app** to Applications.
2. The app isn't notarized (that needs a paid Apple developer account), so
   macOS blocks the first launch. Run this once in Terminal:

   ```sh
   xattr -dr com.apple.quarantine "/Applications/Dynamic Island.app"
   ```

   Or open it, then go to System Settings → Privacy & Security and click
   **Open Anyway**.
3. On first launch macOS asks for Bluetooth access. It's only used for the
   "AirPods connected" alert – everything else works if you say no.

To start it automatically, turn on **Launch at login** in Settings.

## Build from source

You need Xcode or just the Command Line Tools (`xcode-select --install`).

```sh
git clone https://github.com/Achitsak/dynamic-island-mac.git
cd dynamic-island-mac
./build.sh run       # build and launch
./build.sh install   # copy to /Applications and launch
./build.sh dist      # universal (Apple Silicon + Intel) zip in build/
```

Launch with `--demo`, or pick **Play Demo** from the menu bar icon, to see
every state one after another. Handy when changing the UI.

## How Now Playing works

Since macOS 15.4 the private MediaRemote framework only answers apps signed by
Apple, which broke every third-party now playing widget. The workaround, first
found by [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter),
is to load a small library into `/usr/bin/perl`, which *is* signed by Apple.

`MediaBridge/MediaBridge.m` is that library. It prints now playing changes as
JSON lines and reads commands (`toggle`, `next`, `seek 42`, …) from stdin. The
app starts it in the background and it quits together with the app.

If Apple ever closes this gap, the music part stops working; the rest of the
app doesn't depend on it.

## Project layout

```
Sources/DynamicIsland/
  App/          entry point, menu bar item
  Island/       window, shape, layout and state
  Activities/   compact, expanded and alert views
  Services/     now playing, battery, volume, Bluetooth, timer
  Support/      settings, artwork colours
MediaBridge/    MediaRemote helper (Objective-C)
scripts/        app icon renderer
build.sh
```

## Notes

- It uses a private framework, so it can't go on the Mac App Store.
- Tested on a MacBook Air M3 with macOS 26. Intel builds are included but
  untested.
- Not affiliated with Apple. "Dynamic Island" is just the name everyone
  knows this thing by.

## License

[MIT](LICENSE)

---

## ภาษาไทย

Dynamic Island แบบ iPhone สำหรับ MacBook ที่มีรอยบาก แจกฟรีและเปิดซอร์ส
ใช้ได้กับ macOS 14 ขึ้นไป

**ทำอะไรได้บ้าง**

- แสดงเพลงที่กำลังเล่น (Apple Music, Spotify, YouTube ในเบราว์เซอร์ ฯลฯ)
  ชี้เมาส์ที่รอยบากเพื่อเปิดตัวควบคุมเพลง เลื่อนเวลาเพลงได้
- ตั้งเวลาได้จากตัวเกาะหรือไอคอนบนแถบเมนู ถ้าเปิดเพลงอยู่ด้วย จะเห็นปกอัลบั้มทางซ้ายและเวลาที่เหลือทางขวาในเกาะเดียวกัน
- ระหว่างชาร์จ แสดงกำลังไฟที่เข้า (W) และเวลาที่เหลือจนแบตเต็ม
- แจ้งเตือนตอนเสียบสายชาร์จ แบตใกล้หมด ปรับเสียง ปรับแสงหน้าจอ และตอนเชื่อมต่อ AirPods หรืออุปกรณ์บลูทูธ
- กินเครื่องน้อยมาก ตอนว่าง CPU 0% ใช้แรมราว 15–20 MB

**วิธีติดตั้ง**

1. โหลด `DynamicIsland.zip` จากหน้า
   [Releases](https://github.com/Achitsak/dynamic-island-mac/releases/latest)
   แตกไฟล์แล้วลาก **Dynamic Island.app** ไปไว้ในโฟลเดอร์ Applications
2. แอปนี้ไม่ได้ผ่านการรับรองของ Apple (ต้องใช้บัญชีนักพัฒนาแบบเสียเงิน) เปิดครั้งแรกจะโดนบล็อก
   ให้รันคำสั่งนี้ใน Terminal ครั้งเดียว

   ```sh
   xattr -dr com.apple.quarantine "/Applications/Dynamic Island.app"
   ```

   หรือเปิดแอปหนึ่งครั้ง แล้วไปที่ System Settings → Privacy & Security กด **Open Anyway**
3. ครั้งแรกจะขอสิทธิ์บลูทูธ ใช้แค่แจ้งเตือนตอน AirPods เชื่อมต่อ ไม่อนุญาตก็ใช้ส่วนอื่นได้ปกติ

คลิกขวาที่รอยบากเพื่อเปิดหน้าตั้งค่า ปรับขนาด หรือเปิด Launch at login
