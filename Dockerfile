# Lightweight Python 3.11 image
FROM python:3.11-slim

# Prevent memory fragmentation & unbuffer logs
ENV PYTHONUNBUFFERED=1 \
    MALLOC_ARENA_MAX=2 \
    XDG_CACHE_HOME=/tmp/.cache

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

WORKDIR /app

# Copy and install python dependencies from cloud_functions folder
COPY cloud_functions/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Copy source code from cloud_functions folder
COPY cloud_functions/ .

# Set default port
ENV PORT=7860
EXPOSE 7860 8080

# Configure non-root user and cache directories
RUN useradd -m -u 1000 user && \
    mkdir -p /home/user/.cache /tmp/.cache && \
    chown -R user:user /app /home/user /tmp/.cache
USER user
ENV HOME=/home/user \
    XDG_CACHE_HOME=/home/user/.cache \
    PATH=/home/user/.local/bin:$PATH

# Run with Gunicorn production WSGI server (threads=2 and max-requests=25 to strictly bound RAM < 200MB)
CMD ["sh", "-c", "exec gunicorn --bind 0.0.0.0:${PORT:-8080} --workers 1 --threads 2 --worker-class gthread --max-requests 25 --max-requests-jitter 5 --timeout 300 main:app"]
