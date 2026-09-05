# Lightweight Python 3.11 image
FROM python:3.11-slim

# Install system dependencies (ffmpeg for audio transcoding, git/curl)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy and install python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy source code
COPY . .

# Set default port
ENV PORT=8080
EXPOSE 8080

# Run with Gunicorn production WSGI server (timeout 300s for large audio downloads)
CMD exec gunicorn --bind 0.0.0.0:$PORT --workers 1 --threads 8 --timeout 300 main:app
