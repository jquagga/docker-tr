FROM debian:12-slim@sha256:3d5df92588469a4c503adbead0e4129ef3f88e223954011c2169073897547cac AS builder

RUN apt-get update && \
  apt-get -y upgrade &&\
  export DEBIAN_FRONTEND=noninteractive && \
  apt-get install --no-install-recommends -y \
    build-essential \
    ca-certificates \
    cmake \
    curl \
    git \
    gnuradio-dev \
    libairspy-dev \
    libairspyhf-dev \
    libbladerf-dev \
    libboost-all-dev \
    libcurl4-openssl-dev \
    libfreesrp-dev \
    libgmp-dev \
    libhackrf-dev \
    libmirisdr-dev \
    liborc-0.4-dev \
    libpthread-stubs0-dev \
    libsndfile1-dev \
    libsoapysdr-dev \
    libssl-dev \
    libuhd-dev \
    libusb-dev \
    libusb-1.0-0-dev \
    libxtrx-dev \
    pkg-config \
    python3-six

# Compile librtlsdr-dev direct from osmocom for latest updates
RUN cd /tmp && \
  git clone https://gitea.osmocom.org/sdr/rtl-sdr.git && \
  cd rtl-sdr && \
  mkdir build && \
  cd build && \
  cmake .. && \
  make -j$(nproc) && \
  make install && \
  # We need to install both in / and /newroot to use in this image
  # and to copy over to the final image
  make DESTDIR=/newroot install && \
  ldconfig && \
  cd /tmp && \
  rm -rf librtlsdr

# Compile gr-osmosdr ourselves using a fork with various patches included
RUN cd /tmp && \
  git clone https://github.com/racerxdl/gr-osmosdr.git && \
  cd gr-osmosdr && \
  mkdir build && \
  cd build && \
  cmake -DENABLE_NONFREE=TRUE .. && \
  make -j$(nproc) && \
  make install && \
  # We need to install both in / and /newroot to use in this image
  # and to copy over to the final image
  make DESTDIR=/newroot install && \
  ldconfig && \
  cd /tmp && \
  rm -rf gr-osmosdr


WORKDIR /src

RUN git clone https://github.com/robotastic/trunk-recorder /src

WORKDIR /src/build

RUN cmake .. && make -j$(nproc) && make DESTDIR=/newroot install

#Stage 2 build
FROM debian:12-slim@sha256:3d5df92588469a4c503adbead0e4129ef3f88e223954011c2169073897547cac
RUN apt-get update && apt-get -y upgrade && apt-get install --no-install-recommends -y ca-certificates gr-funcube gr-iqbal curl libboost-log1.74.0 \
    libboost-chrono1.74.0 libgnuradio-digital3.10.5 libgnuradio-analog3.10.5 libgnuradio-filter3.10.5 libgnuradio-network3.10.5  \
    libgnuradio-uhd3.10.5 libsoapysdr0.8 soapysdr0.8-module-all libairspyhf1 libfreesrp0 libxtrx0 sox && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /newroot /

# Fix the error message level for SmartNet
RUN mkdir -p /etc/gnuradio/conf.d/ && echo 'log_level = info' >> /etc/gnuradio/conf.d/gnuradio-runtime.conf && ldconfig
WORKDIR /app

# GNURadio requires a place to store some files, can only be set via $HOME env var.
ENV HOME=/tmp

#USER nobody
CMD ["trunk-recorder", "--config=/app/config.json"]
