FROM ubuntu:20.04

RUN apt-get update && apt-get install -y \
    libjpeg-turbo-progs \
    pngcrush \
    gifsicle \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app