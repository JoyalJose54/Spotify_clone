# 🚀 24/7 Cloud Backend Deployment Guide

Deploying this Python backend to the cloud will keep your music ingestion service running **24/7**, eliminating the need to keep your laptop on or run `python main.py` in the terminal.

---

### Option A: Deploy to Render (Recommended & Free)

1. Push your repository to **GitHub**.
2. Go to [render.com](https://render.com) and create a free account.
3. Click **New +** $\rightarrow$ **Web Service**.
4. Connect your `Spotify_clone` GitHub repository.
5. In the settings:
   - **Environment**: `Docker`
   - **Dockerfile Path**: `./cloud_functions/Dockerfile`
   - **Docker Context**: `./cloud_functions`
   - **Instance Type**: `Free`
6. Under **Environment Variables**, add:
   - `CLOUDINARY_CLOUD_NAME` = *Your Cloudinary cloud name*
   - `CLOUDINARY_API_KEY` = *Your Cloudinary API key*
   - `CLOUDINARY_API_SECRET` = *Your Cloudinary API secret*
   - `FIREBASE_CREDENTIALS_JSON` = *The entire JSON contents of your `firebase-key.json` as a single line string*
   - `SHAZAM_KEYS` = *Your RapidAPI Shazam key (optional)*
7. Click **Create Web Service**.
8. Once deployed, Render will provide a public URL (e.g., `https://spotify-ingestion-backend.onrender.com`).

---

### Option B: Deploy to Railway

1. Go to [railway.app](https://railway.app) and sign in with GitHub.
2. Click **New Project** $\rightarrow$ **Deploy from GitHub Repo**.
3. Select your repo and set the Root Directory to `/cloud_functions`.
4. Add your Environment Variables in Railway's Variables tab.
5. Click **Deploy** and generate a public domain.

---

### 📱 Connecting Your Flutter App to the Cloud Backend

Once you have your cloud URL:
1. Open the Flutter app on your device.
2. Go to the app settings / ingestion service or launch the app with:
   ```bash
   flutter run --dart-define=BACKEND_BASE_URL=https://your-app-name.onrender.com
   ```
3. Your app will now download songs, transcode them, and upload them from anywhere in the world, 24/7!
