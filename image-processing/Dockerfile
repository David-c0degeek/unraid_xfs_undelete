FROM ubuntu:20.04

# Avoid prompts from apt
ENV DEBIAN_FRONTEND=noninteractive

# Install required packages
RUN apt-get update && apt-get install -y \
    libjpeg-turbo-progs \
    pngcrush \
    gifsicle \
    file \
    imagemagick \
    && rm -rf /var/lib/apt/lists/*

# Set up working directory
WORKDIR /app

# Copy the script into the container
COPY process_images.sh .

# Make the script executable
RUN chmod +x process_images.sh

# Set the entrypoint to the script
ENTRYPOINT ["/app/process_images.sh"]
