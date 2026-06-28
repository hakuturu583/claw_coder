FROM alpine:3.20

RUN mkdir -p /image-skill-hub

COPY openclaw/skill-hub /image-skill-hub

WORKDIR /image-skill-hub
