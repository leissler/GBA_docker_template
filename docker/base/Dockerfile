FROM debian:bookworm-slim

ARG DEVKITPRO=/opt/devkitpro
ENV DEVKITPRO=$DEVKITPRO

# install basic deps and cleanup in one layer
RUN apt update && apt install -y \
    make build-essential wget curl git \
    && apt autoremove -y && apt clean && rm -rf /var/lib/apt/lists/*

RUN ln -s /proc/mounts /etc/mtab \
    && apt-get update \
    && apt-get install -y --no-install-recommends apt-transport-https ca-certificates wget \
    && mkdir -p /usr/share/keyrings \
    && wget -U "dkp apt" -O /usr/share/keyrings/devkitpro-pub.gpg https://apt.devkitpro.org/devkitpro-pub.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/devkitpro-pub.gpg] https://apt.devkitpro.org stable main" > /etc/apt/sources.list.d/devkitpro.list \
    && apt-get update \
    && apt-get install -y devkitpro-pacman

# Fix the missing /etc/mtab, ignore errors (for example: when already existing)
RUN ln -s /proc/mounts /etc/mtab; exit 0
# sync dkp pacman
RUN dkp-pacman -Sy
# install packages
RUN dkp-pacman -S --noconfirm gba-dev

# set devkitpro variables
ARG DKP_TOOLS_PATH=$DEVKITPRO/tools/bin
ENV DKP_TOOLS_PATH=$DKP_TOOLS_PATH

WORKDIR /source

# Add the entrypoint script to the Docker image
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Set the entrypoint to the script
ENTRYPOINT ["/entrypoint.sh", "bash", "-l"]
