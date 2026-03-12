FROM debian:bookworm-slim

ARG DEVKITPRO=/opt/devkitpro
ENV DEVKITPRO=${DEVKITPRO}

# Core build dependencies + tools used by the existing base/dusk images
RUN apt-get update && apt-get install -y --no-install-recommends \
    make build-essential wget curl git \
    cmake bash python3 python3-pip dpkg \
    apt-transport-https ca-certificates \
    && ln -sf /usr/bin/python3 /usr/bin/python \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# devkitPro package feed + gba-dev toolchain
RUN ln -sf /proc/mounts /etc/mtab || true \
    && mkdir -p /usr/share/keyrings \
    && wget -U "dkp apt" -O /usr/share/keyrings/devkitpro-pub.gpg https://apt.devkitpro.org/devkitpro-pub.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/devkitpro-pub.gpg] https://apt.devkitpro.org stable main" > /etc/apt/sources.list.d/devkitpro.list \
    && apt-get update \
    && apt-get install -y devkitpro-pacman \
    && dkp-pacman -Sy \
    && dkp-pacman -S --noconfirm gba-dev \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

ARG DKP_TOOLS_PATH=${DEVKITPRO}/tools/bin
ENV DKP_TOOLS_PATH=${DKP_TOOLS_PATH}

# Dusk extras
RUN git clone https://github.com/redthing1/crunch.git /tmp/crunch \
    && cd /tmp/crunch \
    && mkdir build && cd build \
    && cmake .. \
    && make -j"$(nproc)" \
    && cp crunch_gen ${DKP_TOOLS_PATH} \
    && rm -rf /tmp/crunch

RUN git clone https://github.com/redthing1/Tiled2GBA.git /tmp/tiled2gba \
    && cd /tmp/tiled2gba/converter \
    && mkdir build && cd build \
    && cmake .. \
    && make -j"$(nproc)" \
    && cp Tiled2GBA ${DKP_TOOLS_PATH} \
    && rm -rf /tmp/tiled2gba

RUN git clone https://github.com/edubart/nelua-lang.git /tmp/nelua-lang \
    && cd /tmp/nelua-lang \
    && make \
    && make install \
    && rm -rf /tmp/nelua-lang

RUN curl -fsS https://dlang.org/install.sh | bash -s install ldc-1.30.0 \
    && echo "source ~/dlang/ldc-1.30.0/activate" >> ~/.bashrc

# Butano
RUN git clone https://github.com/GValiente/butano.git /butano_src
ENV LIBBUTANOABS=/butano_src/butano
