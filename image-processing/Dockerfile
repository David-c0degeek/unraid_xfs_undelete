FROM ubuntu:20.04

RUN apt-get update && apt-get install -y \
    libjpeg-turbo-progs \
    pngcrush \
    gifsicle \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy the processing script into the image
COPY process_images.sh /app/

# Make the script executable
RUN chmod +x /app/process_images.sh

# Set the script to run when the container starts
ENTRYPOINT ["/app/process_images.sh"]
