# 🚀 24/7 Backend Deployment Guide (Termux & Local)

Running this Python backend locally or on Android (Termux) gives you **100% unlimited RAM, zero cold starts, and zero risk of YouTube bot blocking** (because it runs directly from your residential IP rather than a datacenter IP).

The backend features a **hybrid pipeline**:
1. **Tier 1 (SpotiFLAC)**: Downloads studio-master lossless FLAC via Tidal/Qobuz with official Spotify metadata.
2. **Tier 2 (YouTube Fallback)**: If a track is **Malayalam, Tamil, regional, or unstreamed**, SpotiFLAC will seamlessly fall back to YouTube (`yt-dlp`) with anti-blocking Android client emulation.

---

## 📱 Option A: Run 24/7 on Android Phone with Termux (Recommended)

Running on Termux keeps your backend running 24/7 directly on your phone with zero RAM restrictions and no laptop required.

### 1. Install System Dependencies in Termux
```bash
pkg update && pkg upgrade -y
pkg install python ffmpeg nodejs-lts git -y
```

### 2. Clone Your Repository
```bash
git clone https://github.com/JoyalJose54/Spotify_clone.git
cd Spotify_clone/cloud_functions
```

### 3. Install Python Dependencies
```bash
pip install -r requirements.txt
```

### 4. Create `.env` File
```bash
nano .env
```
Paste your Cloudinary and Firebase configuration:
```ini
CLOUDINARY_CLOUD_NAME=your_name
CLOUDINARY_API_KEY=your_key
CLOUDINARY_API_SECRET=your_secret
FIREBASE_CREDENTIALS_JSON=../database/firebase-key.json
SPOTIFLAC_REGISTRIES=https://raw.githubusercontent.com/zarzet/SpotiFLAC-Extension/main/registry.json
```
*(Press `Ctrl + O` and `Enter` to save, `Ctrl + X` to exit).*

Ensure your `firebase-key.json` exists in `Spotify_clone/database/firebase-key.json`.

### 5. Prevent Android from Killing Termux in the Background
```bash
termux-wake-lock
```
*(Also set Termux Battery usage to **Unrestricted** in Android App Settings).*

### 6. Start the Backend
```bash
python main.py
```
Your Flutter app can now connect directly via `http://127.0.0.1:8080` (if running on the same phone) or your phone's Wi-Fi IP.

---

## 💻 Option B: Cloudflare Tunnel (Run on PC or Termux with Public HTTPS URL)

If you want a public HTTPS URL so your Flutter app can connect from anywhere (even outside your home Wi-Fi):

1. **Install cloudflared**:
   - On Windows: `winget install Cloudflare.cloudflared`
   - On Termux: `pkg install cloudflared -y`
2. **Start the backend**:
   ```bash
   python main.py
   ```
3. **In a second terminal, launch the tunnel**:
   ```bash
   cloudflared tunnel --url http://localhost:8080
   ```
4. Cloudflare will output a public URL like:
   `https://random-words.trycloudflare.com`
5. Paste that URL into your Flutter app's backend settings, and you're good to go!

---

## 📱 Connecting Your Flutter App to the Backend

1. Launch your Flutter app.
2. In `lib/services/ingestion_service.dart`, the default backend is set to:
   ```dart
   const String _kBackendBase = String.fromEnvironment('BACKEND_BASE_URL', defaultValue: 'http://127.0.0.1:8080');
   ```
3. You can also change the URL anytime inside the app by going to the Ingestion screen and updating the **Backend Server URL**.
