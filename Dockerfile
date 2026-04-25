FROM dart:stable

# Install yt-dlp and dependencies
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install --break-system-packages yt-dlp

# Setup app
WORKDIR /app
COPY pubspec.* ./
RUN dart pub get

COPY . .

# Expose port
EXPOSE 8080

# Start server
CMD ["dart", "run", "bin/server.dart"]
