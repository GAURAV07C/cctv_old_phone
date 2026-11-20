# 📹 Smart CCTV - Old Phone to CCTV (Anywhere Access)

Apne purane Android phone ko ek smart, low-latency, encrypted CCTV camera me badalne ke liye full Flutter + WebRTC project.

---

## 🌟 Features

1. **Anywhere Access (Duniya me kahin se bhi dekhein):**
   - WebRTC Peer-to-Peer technology + Google free STUN servers.
   - Purana phone ghar ke Wi-Fi par ho aur aap office me 4G/5G par hon, tab bhi direct connection banta hai. Zero server bandwidth cost!

2. **Stealth Mode (Screen-Off / OLED Black Screen):**
   - Ek tap me screen pitch black ho jati hai (0% brightness).
   - Phone bilkul band lagta hai, camera background me capture karta rehta hai.
   - OLED screen par zero display battery kharch hoti hai.
   - Double-tap karke wapas normal screen khol sakte hain.

3. **Smart Battery Optimization:**
   - 720p @ 15-20 FPS (CCTV ke liye smooth, CPU aur battery par koi load nahi).
   - On-demand streaming: Jab tak koi viewer connect nahi hota, phone ultra-low power standby me rehta hai.

4. **Multi-Platform Viewer:**
   - **Flutter App**: Naye phone me app open karke "Viewer Mode" chala sakte hain.
   - **Web Browser**: Kisi bhi laptop, PC ya iPhone ke Chrome/Safari browser me `http://<server-ip>:3000` khol kar direct live feed dekh sakte hain (koi app install kiye bina!).

5. **Remote Controls:**
   - Viewer se baithkar purane phone ki **Flashlight on/off** kar sakte hain.
   - **Front/Back camera switch** kar sakte hain.
   - **Audio mute/unmute** kar sakte hain.

---

## 📂 Project Structure

```
cctv_old_phone/
├── cctv_app/                     # Flutter Application (Android + Web)
│   ├── lib/
│   │   ├── main.dart             # App Entry Point
│   │   ├── screens/
│   │   │   ├── home_screen.dart   # Role Selection (Camera Mode vs Viewer Mode)
│   │   │   ├── camera_screen.dart # Camera stream, Stealth black screen, Wakelock
│   │   │   └── viewer_screen.dart # Remote player, controls (Flash, Switch, Audio)
│   │   └── services/
│   │       ├── webrtc_service.dart    # WebRTC P2P Video/Audio stream engine
│   │       └── signaling_service.dart # Standard WebSocket client
│   └── pubspec.yaml
│
├── signaling_server/             # WebRTC Signaling Server (Node.js)
│   ├── server_standalone.js      # Zero-dependency standalone server
│   ├── public/
│   │   └── index.html            # Web Viewer UI for PC/Laptop/iPhone browsers
│   └── package.json
│
├── run_server.bat                # 1-Click Server Runner on Windows
└── build_apk.bat                 # 1-Click Android APK Builder
```

---

## 🚀 Kaise Chalayein (Step-by-Step Guide)

### Step 1: Signaling Server Start Karein
Laptop par `run_server.bat` par double-click karein ya terminal me run karein:
```bash
node signaling_server/server_standalone.js
```
Aapko output dikhega:
```
Standalone CCTV WebRTC Signaling Server Running!
Port: 3000
Web Viewer: http://localhost:3000
Network URL: http://<Aapka-Laptop-IP>:3000
```

> **Tip (Anywhere Access 24/7):** Agar aap ghar se bahar se bhi bina laptop on rakhe stream dekhna chahte hain, toh is `signaling_server` folder ko [Render.com](https://render.com) ya [Railway.app](https://railway.app) par free me deploy kar sakte hain. Wahan se aapko ek permanent URL mil jayega (e.g. `https://my-cctv.onrender.com`).

---

### Step 2: Purane Phone Par App Chalayein (Camera Mode)

1. Purane phone ko laptop se USB se connect karein aur APK build/install karein:
   ```bash
   cd cctv_app
   flutter run -d <phone-id>
   ```
   *Ya fir `build_apk.bat` run karke APK generate karein aur phone me transfer karke install kar lein.*

2. App open karein:
   - **Server Settings (Top-Right Gear icon):** Apne laptop ka local IP daalein (e.g. `http://192.168.1.15:3000`) ya deployed cloud URL.
   - **Room ID:** Koi bhi code rakhein (e.g. `HOME-101`).
   - Click **"Start as Camera"**.
3. Camera start ho jayega.
4. **"Turn Screen OFF (Stealth Mode)"** button dabayein:
   - Screen pitch black ho jayegi.
   - Phone ek stand par laga kar charger se connect kar dein.

---

### Step 3: Live Feed Dekhein (Viewer)

Aap 2 tareeqon se dekh sakte hain:

#### Option A: Laptop / Doosre Phone ke Browser me
1. Chrome browser me open karein: `http://<server-ip>:3000` (ya deployed URL).
2. Wahi Room ID daalein (e.g. `HOME-101`).
3. Click **"Connect"** — Live stream sub-second latency ke sath start ho jayegi!
4. Screen par Flashlight toggle aur Camera switch ke buttons bhi milenge.

#### Option B: Naye Phone ke Flutter App me
1. Naye phone me app kholiye.
2. Select **"Viewer Mode"**.
3. Wahi Room ID daal kar live stream enjoy karein.
