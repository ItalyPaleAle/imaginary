ARG GOLANG_VERSION=1.18.5
FROM golang:${GOLANG_VERSION}-bullseye as builder

# Version of dependencies: libvips, libcgif, libspng
ARG LIBVIPS_VERSION=8.13.0
ARG LIBCGIF_VERSION=0.3.0
ARG LIBSPNG_VERSION=0.7.2

# Install additional OS packages
# Install then libspng, libcgif, and libvips from source
RUN DEBIAN_FRONTEND=noninteractive \
  apt-get update && \
  apt-get install --no-install-recommends -y \
  ca-certificates \
  automake build-essential meson curl \
  gobject-introspection gtk-doc-tools libglib2.0-dev libjpeg62-turbo-dev \
  libwebp-dev libtiff5-dev libgif-dev libexif-dev libxml2-dev libpoppler-glib-dev \
  swig libmagickwand-dev libpango1.0-dev libmatio-dev libopenslide-dev libcfitsio-dev \
  libgsf-1-dev fftw3-dev liborc-0.4-dev librsvg2-dev libimagequant-dev libheif-dev && \
  # libspng
  cd /tmp && \
  curl -fsSL https://github.com/randy408/libspng/archive/refs/tags/v${LIBSPNG_VERSION}.tar.gz -o libspng-${LIBSPNG_VERSION}.tar.gz && \
  tar zvxf libspng-${LIBSPNG_VERSION}.tar.gz && \
  rm libspng-${LIBSPNG_VERSION}.tar.gz && \
  cd /tmp/libspng-${LIBSPNG_VERSION} && \
  meson setup --prefix=/usr/local build --buildtype=release && \
  meson install -C build && \
  # libcgif
  cd /tmp && \
  curl -fsSL https://github.com/dloebl/cgif/archive/refs/tags/V${LIBCGIF_VERSION}.tar.gz -o cgif-${LIBCGIF_VERSION}.tar.gz && \
  tar zvxf cgif-${LIBCGIF_VERSION}.tar.gz && \
  rm cgif-${LIBCGIF_VERSION}.tar.gz && \
  cd /tmp/cgif-${LIBCGIF_VERSION} && \
  meson setup --prefix=/usr/local build && \
  meson install -C build && \
  # libvips
  cd /tmp && \
  curl -fsSLO https://github.com/libvips/libvips/releases/download/v${LIBVIPS_VERSION}/vips-${LIBVIPS_VERSION}.tar.gz && \
  tar zvxf vips-${LIBVIPS_VERSION}.tar.gz && \
  rm vips-${LIBVIPS_VERSION}.tar.gz && \
  cd /tmp/vips-${LIBVIPS_VERSION} && \
	CFLAGS="-g -O3" CXXFLAGS="-D_GLIBCXX_USE_CXX11_ABI=0 -g -O3" \
    ./configure \
    --disable-debug \
    --disable-dependency-tracking \
    --disable-introspection \
    --disable-static \
    --enable-gtk-doc-html=no \
    --enable-gtk-doc=no \
    --enable-pyvips8=no && \
  make && \
  make install && \
  ldconfig

WORKDIR ${GOPATH}/src/github.com/h2non/imaginary

# Cache go modules
ENV GO111MODULE=on

COPY go.mod .
COPY go.sum .

RUN go mod download

# Copy imaginary sources
COPY . .

# Compile imaginary
RUN go build -a \
    -o ${GOPATH}/bin/imaginary \
    -ldflags="-s -w -h -X main.Version=${IMAGINARY_VERSION}" \
    github.com/h2non/imaginary

FROM debian:bullseye-slim

ARG IMAGINARY_VERSION

LABEL maintainer="tomas@aparicio.me" \
      org.label-schema.description="Fast, simple, scalable HTTP microservice for high-level image processing with first-class Docker support" \
      org.label-schema.schema-version="1.0" \
      org.label-schema.url="https://github.com/h2non/imaginary" \
      org.label-schema.vcs-url="https://github.com/h2non/imaginary" \
      org.label-schema.version="${IMAGINARY_VERSION}"

COPY --from=builder /usr/local/lib /usr/local/lib
COPY --from=builder /go/bin/imaginary /usr/local/bin/imaginary
COPY --from=builder /etc/ssl/certs /etc/ssl/certs

# Install runtime dependencies
RUN DEBIAN_FRONTEND=noninteractive \
  apt-get update && \
  apt-get install --no-install-recommends -y \
  procps libglib2.0-0 libjpeg62-turbo libopenexr25 \
  libwebp6 libwebpmux3 libwebpdemux2 libtiff5 libgif7 libexif12 libxml2 libpoppler-glib8 \
  libmagickwand-6.q16-6 libpango1.0-0 libmatio11 libopenslide0 libjemalloc2 \
  libgsf-1-114 fftw3 liborc-0.4-0 librsvg2-2 libcfitsio9 libimagequant0 libheif1 && \
  ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
  apt-get autoremove -y && \
  apt-get autoclean && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
ENV LD_PRELOAD=/usr/local/lib/libjemalloc.so

# Server port to listen
ENV PORT 9000

# Drop privileges for non-UID mapped environments
USER nobody

# Run the entrypoint command by default when the container starts.
ENTRYPOINT ["/usr/local/bin/imaginary"]

# Expose the server TCP port
EXPOSE ${PORT}
