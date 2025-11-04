FROM debian:12-slim@sha256:4d9b5b6cf5f643fdf2887eab79f2f916363704184ab270bf4a5c1d65102d03d2 AS builder

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
    libboost-all-dev \
    libcurl4-openssl-dev \
    libgmp-dev \
    liborc-0.4-dev \
    libpthread-stubs0-dev \
    libssl-dev \
    libuhd-dev \
    libusb-dev \
    libusb-1.0-0-dev \
    pkg-config \
    debhelper

# Compile librtlsdr-dev direct from osmocom for latest updates
WORKDIR /rtlsdr
RUN git clone https://gitea.osmocom.org/sdr/rtl-sdr.git /rtlsdr && \
  export DEB_BUILD_OPTIONS=noautodbgsym && \
  dpkg-buildpackage -b -ui -uc -us 
RUN dpkg -i --force-all ../*.deb && ldconfig

# Compile gr-osmosdr from upstream for latest updates
WORKDIR /grosmosdr
RUN git clone https://gitea.osmocom.org/sdr/gr-osmosdr /grosmosdr && \
  # Settle on haswell as a sensible build option herejj
  sed -i 's/-march=native/-march=haswell/g' CMakeLists.txt && \
  mkdir build && cd build && \
  # Make sure we have RTL and Airspy and remove the rest
  cmake -DENABLE_PYTHON=OFF \
  -DENABLE_RTL=ON -DENABLE_AIRSPY=ON -DENABLE_FCD=OFF \
  -DENABLE_FILE=OFF -DENABLE_UHD=OFF -DENABLE_MIRI=OFF \
  -DENABLE_HACKRF=OFF -DENABLE_BLADERF=OFF -DENABLE_RFSPACE=OFF \
  -DENABLE_AIRSPYHF=OFF -DENABLE_SOAPY=OFF -DENABLE_REDPITAYA=OFF \
  -DENABLE_FREESRP=OFF -DENABLE_XTRX=OFF .. && \
  make -j$(nproc) && \
  make install && \
  # We need to install both in / and /newroot to use in this image
  # and to copy over to the final image
  make DESTDIR=/newroot install && \
  ldconfig 

# Now let's build trunk-recorder
WORKDIR /src
RUN git clone https://github.com/robotastic/trunk-recorder /src && \
    git checkout 4d90da149e2fc39e5cbd2643bd50bbbc6f940415 # 5.0.1
WORKDIR /src/build
RUN cmake .. && make -j$(nproc) && make DESTDIR=/newroot install



# Stage 2 build *****************************************************
FROM debian:12-slim@sha256:4d9b5b6cf5f643fdf2887eab79f2f916363704184ab270bf4a5c1d65102d03d2
WORKDIR /app
# Debian needs contrib and non-free for fdkaac so that's what this sed enables.
# It's disabled though as I don't use it.
#RUN sed -i 's/^Components: main$/& contrib non-free/' /etc/apt/sources.list.d/debian.sources&& 
RUN apt-get update && \
    apt-get -y upgrade && apt-get install --no-install-recommends -y ca-certificates curl libboost-log1.74.0 \
    libboost-chrono1.74.0 libgnuradio-digital3.10.5 libgnuradio-analog3.10.5 libgnuradio-filter3.10.5 libgnuradio-network3.10.5  \
    libgnuradio-uhd3.10.5 libairspy0 sox 

# Copy over gr-osmo, trunk-recorder and the rtlsdr deb from builder
COPY --from=builder /newroot /
COPY --from=builder /*.deb /app/deb/

# This installed the rtlsdr deb we built in builder and then clears lists and
# removes manpages, etc which won't be used
RUN dpkg -i --force-all /app/deb/*.deb && rm -rf /app/deb && \
    rm -rf /var/lib/apt/lists/* && \
    rm -rf /usr/share/{doc,man,info} && rm -rf /usr/local/share/{doc,man,info}

# Fix the error message level for SmartNet
RUN mkdir -p /etc/gnuradio/conf.d/ && echo 'log_level = info' >> /etc/gnuradio/conf.d/gnuradio-runtime.conf && ldconfig

# GNURadio requires a place to store some files, can only be set via $HOME env var.
ENV HOME=/tmp

CMD ["trunk-recorder", "--config=/app/config.json"]
