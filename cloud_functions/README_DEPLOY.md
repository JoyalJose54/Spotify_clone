# 🚀 24/7 Backend Deployment Guide (PC & Termux)

Running this Python backend on your PC or on Android (Termux) provides **unlimited RAM, zero cold starts, and zero YouTube bot blocking** because it uses your home residential network rather than shared datacenter IP pools.

The backend features a **high-speed ingestion pipeline**:
1. **Direct YouTube / YT Music Retrieval**: Downloads high-fidelity audio via `yt-dlp` using optimized VisionOS / Android VR client emulation in ~3–5 seconds.
2. **Parallel Processing**: FFmpeg transcodes audio to 256k AAC M4A while album artwork and audio upload concurrently to Cloudinary CDN and Firestore.

---

## 💻 Option A: Permanent Public Tunnel on PC (Recommended)

Run the backend on your PC and access it anywhere in the world (even over mobile data) using your permanent Ngrok domain with **zero URL changes on PC reboots**.

### 1. Requirements on PC
- Python 3.11+
- FFmpeg installed in system PATH
- Node.js installed in system PATH
- Ngrok installed (`winget install ngrok`)

### 2. Configure Environment (.env)
Inside `cloud_functions/.env`:
```ini
CLOUDINARY_CLOUD_NAME=your_name
CLOUDINARY_API_KEY=your_key
CLOUDINARY_API_SECRET=your_secret
FIREBASE_CREDENTIALS_JSON=../database/firebase-key.json
```

### 3. Launching the Backend

- **Visible Mode (Inspect live logs)**:
  Double-click `run_ngrok_backend.bat` in the project root.
- **Silent Background Mode (Zero terminal windows)**:
  Double-click `run_backend_silent.vbs`.
- **Automatic Startup on PC Boot**:
  Press `Win + R`, type `shell:startup`, and place a shortcut to `run_backend_silent.vbs` inside that folder. Whenever your PC starts, the backend will run invisibly in the background.
- **Stop Backend**:
  Double-click `stop_backend.bat` to terminate both Python and tunnel processes.

---

## 📱 Option B: Run 24/7 on Android Phone with Termux

Running on Termux keeps your backend active 24/7 directly on an Android device with zero PC requirement:

### 1. Install System Dependencies in Termux
```bash
pkg update && pkg upgrade -y
pkg install python ffmpeg nodejs-lts git clang -y
```

### 2. Clone Repository & Setup
```bash
git clone https://github.com/JoyalJose54/Spotify_clone.git
cd Spotify_clone/cloud_functions
pip install -r requirements.txt
cp .env.example .env
nano .env
```

### 3. Keep Termux Active
```bash
termux-wake-lock
python main.py
```
*(Set Termux battery usage to **Unrestricted** in Android App Settings).*

---

## 🌐 Option C: Local Home Wi-Fi (Ultra Low Latency)

When your phone is connected to the same home Wi-Fi network as your PC:
- Connect directly to: `http://10.0.9.179:8080`
- No cloud tunnel latency, direct peer-to-peer data ingestion!

---

## 📱 Connecting Your Flutter App

Open your Spotify app and tap the **Backend Status** badge (top-right of the Ingestion screen) to choose your connection mode:
1. **Use Cloudflare / Tunnel (Default)**: Connects to `https://removal-magnolia-overhand.ngrok-free.dev` from anywhere.
2. **Local Wi-Fi**: Connects to `http://10.0.9.179:8080` when on the same Wi-Fi.
3. **Custom URL**: Enter any custom IP/domain anytime.
