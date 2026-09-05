# Lightweight Python 3.11 image
FROM python:3.11-slim

# Install system dependencies & Node.js 22 LTS (required by yt-dlp 2025 JS challenge solver)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    git \
    curl \
    ca-certificates \
    gnupg \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

ENV XDG_CACHE_HOME=/tmp/.cache
WORKDIR /app

# Copy and install python dependencies
COPY requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Copy source code
COPY . .

# Set default port and SpotiFLAC registries
ENV PORT=8080
ENV SPOTIFLAC_REGISTRIES=https://raw.githubusercontent.com/zarzet/SpotiFLAC-Extension/main/registry.json
EXPOSE 8080

# Run with Gunicorn production WSGI server (timeout 300s for large audio downloads)
CMD exec gunicorn --bind 0.0.0.0:$PORT --workers 1 --threads 8 --timeout 300 main:app
