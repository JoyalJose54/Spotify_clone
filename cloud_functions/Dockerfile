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
ENV PORT=7860
ENV SPOTIFLAC_REGISTRIES=https://raw.githubusercontent.com/zarzet/SpotiFLAC-Extension/main/registry.json
EXPOSE 7860 8080

# Configure non-root user for Hugging Face Spaces compatibility
RUN useradd -m -u 1000 user && chown -R user:user /app
USER user
ENV HOME=/home/user \
    PATH=/home/user/.local/bin:$PATH

# Run with Gunicorn production WSGI server (threads=2 and max-requests=25 to strictly bound RAM < 200MB)
CMD ["sh", "-c", "exec gunicorn --bind 0.0.0.0:${PORT:-8080} --workers 1 --threads 2 --max-requests 25 --timeout 300 main:app"]
