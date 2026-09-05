# 🚀 24/7 Cloud Backend Deployment Guide

Deploying this Python backend online keeps your music ingestion service running **24/7**, eliminating the need to run `python main.py` on your laptop every time you want to add music.

The backend features a **hybrid pipeline**:
1. **Tier 1 (SpotiFLAC)**: Downloads studio-master lossless FLAC via Tidal/Qobuz with official Spotify metadata.
2. **Tier 2 (YouTube Fallback)**: If a track is **Malayalam, Tamil, regional, or unstreamed**, SpotiFLAC will seamlessly fall back to YouTube (`yt-dlp`) with anti-blocking Android client emulation.

---

## 🏆 Option A: Deploy to Render (Recommended — 100% Free, NO Credit Card Required)

Render lets you deploy a Docker container completely free just by connecting your GitHub account. **No credit card, no debit card, and no payment verification is needed.**

Your Flutter app already has your Render backend configured (`https://spotify-clone-uehl.onrender.com`)!

### 1. Push Your Code to GitHub
Ensure all latest changes are committed and pushed to your GitHub repository:
```bash
git add .
git commit -m "Add hybrid SpotiFLAC + YouTube fallback and anti-blocking config"
git push origin main
```

### 2. Configure Render Web Service
1. Go to [dashboard.render.com](https://dashboard.render.com/) and sign in with GitHub.
2. Click your existing service or click **New +** $\rightarrow$ **Web Service**.
3. Select your `Spotify_clone` repository.
4. Set the following build settings:
   - **Name**: `spotify-ingestion-backend`
   - **Environment**: `Docker`
   - **Region**: Oregon (US West) or Frankfurt (EU)
   - **Dockerfile Path**: `./Dockerfile` (or `./cloud_functions/Dockerfile`)
   - **Instance Type**: `Free`
5. Under **Environment Variables**, ensure you have:
   - `CLOUDINARY_CLOUD_NAME` = *Your Cloudinary cloud name*
   - `CLOUDINARY_API_KEY` = *Your Cloudinary API key*
   - `CLOUDINARY_API_SECRET` = *Your Cloudinary API secret*
   - `FIREBASE_CREDENTIALS_JSON` = *The entire JSON contents of your `firebase-key.json` as a single line string*
6. Click **Save Changes** / **Manual Deploy** $\rightarrow$ **Deploy latest commit**.

### 3. Keep Render Awake 24/7 (Prevent 15-Minute Idle Sleep)
Render's free tier spins down if it receives no requests for 15 minutes. To keep it awake 24/7 with zero cold starts:
1. Go to [cron-job.org](https://cron-job.org) or [uptimerobot.com](https://uptimerobot.com) (both 100% free, no credit card).
2. Create a free account.
3. Add a new monitor / cron job:
   - **URL**: `https://<your-render-app-url>.onrender.com/ping`
   - **Interval**: Every 10 minutes.
4. Render will now stay awake 24/7!

---

## 💻 Option B: Cloudflare Tunnel (Run on Your PC with Zero Cost & Unlimited RAM)

If you ever want **100% unlimited RAM, zero cold starts, and zero risk of YouTube blocking** (because it runs from your home residential IP):
You can expose your local Python backend to a permanent HTTPS URL using **Cloudflare Tunnel (cloudflared)**:

1. Download `cloudflared` (free, no account or card required):
   ```powershell
   winget install Cloudflare.cloudflared
   ```
2. Start your local backend:
   ```bash
   python cloud_functions/main.py
   ```
3. In a second terminal, launch the tunnel:
   ```bash
   cloudflared tunnel --url http://localhost:8080
   ```
4. Cloudflare will instantly output a public URL like:
   `https://random-words.trycloudflare.com`
5. Paste that URL into your Flutter app's backend settings, and you're good to go!

---

## ☁️ Option C: Oracle Cloud Always Free (Requires Credit Card for Verification)

If you acquire a credit or debit card in the future:
Oracle Cloud provides **4 OCPUs, 24 GB of RAM, and a dedicated static IP** 100% free forever. It requires a card solely for 1-time identity verification (a temporary ~$1 authorization hold that is immediately refunded).

1. Sign up at [oracle.com/cloud/free](https://www.oracle.com/cloud/free/).
2. Create an Ubuntu VM on Ampere A1 (ARM, 4 OCPUs, 24 GB RAM).
3. Open port 8080 in the VCN Security List and Ubuntu firewall:
   ```bash
   sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 8080 -j ACCEPT
   ```
4. Run via Docker:
   ```bash
   sudo docker run -d --name spotify-backend --restart always -p 8080:8080 ... spotify-backend
   ```

---

## 📱 Connecting Your Flutter App to the Backend

1. Launch your Flutter app.
2. In `lib/services/ingestion_service.dart`, the default backend is set to:
   ```dart
   const String _kBackendBase = String.fromEnvironment('BACKEND_BASE_URL', defaultValue: 'https://spotify-clone-uehl.onrender.com');
   ```
3. If using a new URL, pass it when running the app:
   ```bash
   flutter run --dart-define=BACKEND_BASE_URL=https://your-service.onrender.com
   ```
4. Now, any song you ingest—whether international, Bollywood, or local Malayalam tracks—will be processed automatically with high quality!
