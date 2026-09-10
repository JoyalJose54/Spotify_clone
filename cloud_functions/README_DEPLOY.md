# 🚀 24/7 Backend Deployment Guide (Termux & Local)

Running this Python backend locally or on Android (Termux) gives you **100% unlimited RAM, zero cold starts, and zero risk of YouTube bot blocking** (because it runs directly from your residential IP rather than a datacenter IP).

The backend features a **high-speed ingestion pipeline**:
1. **Direct YouTube / YT Music Retrieval**: Downloads high-fidelity audio via `yt-dlp` using anti-blocking Android client emulation in ~3–5 seconds.
2. **Parallel Processing**: FFmpeg transcodes audio to 256k AAC M4A while album artwork and audio upload concurrently to Cloudinary.

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

## ☁️ Option C: Deploy on Render (Free Tier - 512MB RAM)

With SpotiFLAC removed, the backend runs comfortably within **150MB–220MB RAM**, easily fitting inside Render's **512MB Free Tier limit**.

### 1. Create a New Web Service on Render
1. Go to [dashboard.render.com](https://dashboard.render.com) and click **New + > Web Service**.
2. Connect your GitHub repository (`Spotify_clone`).
3. Select **Docker** as the Runtime (it will use the project's `Dockerfile` to install ffmpeg and Node.js automatically).
4. Instance Type: Select **Free (512 MB RAM, 0.1 CPU)**.

### 2. Configure Environment Variables on Render
Under **Environment Variables**, add:
| Key | Value | Notes |
| :--- | :--- | :--- |
| `CLOUDINARY_CLOUD_NAME` | *your-cloud-name* | Required for media storage |
| `CLOUDINARY_API_KEY` | *your-api-key* | Required |
| `CLOUDINARY_API_SECRET` | *your-api-secret* | Required |
| `FIREBASE_CREDENTIALS_JSON` | *paste contents of firebase-key.json* | Direct JSON string of service account key |
| `YOUTUBE_COOKIES_BASE64` | *base64 encoded cookies.txt* | Optional but recommended for datacenter reliability |

### 3. Preventing the 15-Minute "Cooloff / Inactivity Sleep"
Render puts Free services to sleep after 15 minutes of inactivity. We provide two solutions:
- **Built-in Auto Keep-Alive**: The backend automatically detects Render's `RENDER_EXTERNAL_URL` and starts a background heartbeat thread that pings `/ping` every 10 minutes.
- **External Cron Ping (Recommended 100% Guarantee)**:
  1. Go to [cron-job.org](https://cron-job.org) or [uptimerobot.com](https://uptimerobot.com) (both 100% free).
  2. Create a new monitor to send an HTTP GET request to:
     `https://your-service-name.onrender.com/ping`
  3. Set the schedule to every **10 or 12 minutes**.
  4. Render will stay awake 24/7 with zero cold starts! (Render gives 750 free hours/month, and a full 31-day month is only 744 hours, so 1 service stays within the free allowance).

---

## 📱 Connecting Your Flutter App to the Backend

1. Launch your Flutter app.
2. In `lib/services/ingestion_service.dart`, the default backend is set to:
   ```dart
   const String _kBackendBase = String.fromEnvironment('BACKEND_BASE_URL', defaultValue: 'http://127.0.0.1:8080');
   ```
3. You can also change the URL anytime inside the app by going to the Ingestion screen and updating the **Backend Server URL** with your Render URL: `https://your-service-name.onrender.com`.
