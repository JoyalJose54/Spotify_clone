# Lightweight Python 3.11 image
FROM python:3.11-slim

# Install system dependencies (ffmpeg for audio transcoding, git/curl, nodejs for JS challenges)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    git \
    curl \
    nodejs \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy and install python dependencies from cloud_functions folder
COPY cloud_functions/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Copy source code from cloud_functions folder
COPY cloud_functions/ .

# Set default port and SpotiFLAC registries
ENV PORT=8080
ENV SPOTIFLAC_REGISTRIES=https://raw.githubusercontent.com/zarzet/SpotiFLAC-Extension/main/registry.json
EXPOSE 8080

# Run with Gunicorn production WSGI server (timeout 300s for large audio downloads)
CMD exec gunicorn --bind 0.0.0.0:$PORT --workers 1 --threads 8 --timeout 300 main:app
