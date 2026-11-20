#!/usr/bin/env bash
set -oue pipefail

mkdir -p /tmp/bin

# ==============================================================================
# Shared Build Toolchain
# ==============================================================================
dnf5 install -y \
  cargo \
  rustc \
  clang \
  llvm \
  lld \
  gcc \
  gcc-c++ \
  make \
  cmake \
  git \
  curl \
  tar \
  gzip \
  pkgconf-pkg-config

TARGET_TRIPLE="x86_64-unknown-linux-gnu"
export CC=clang
export CXX=clang++
export AR=llvm-ar
export RANLIB=llvm-ranlib
export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_RUSTFLAGS="-C target-cpu=znver3 -C link-arg=-fuse-ld=lld"
export OPENSSL_NO_VENDOR=1
export LIBSQLITE3_SYS_USE_PKG_CONFIG=1

ZEN3_C_FLAGS="-O3 -march=znver3 -mtune=znver3 -flto=thin -pipe"
export CFLAGS_x86_64_unknown_linux_gnu="${ZEN3_C_FLAGS}"
export CXXFLAGS_x86_64_unknown_linux_gnu="${ZEN3_C_FLAGS}"

cargo_build() {
  cargo install --root /tmp --locked --target "${TARGET_TRIPLE}" "$@"
}

# Helper for crates pulling in aws-lc-sys / jitterentropy (which requires -O0 on jitterentropy-base.c)
cargo_build_no_c_opt() {
  (
    unset CFLAGS CXXFLAGS CFLAGS_x86_64_unknown_linux_gnu CXXFLAGS_x86_64_unknown_linux_gnu
    export CFLAGS_x86_64_unknown_linux_gnu="-march=znver3 -mtune=znver3 -pipe"
    export CXXFLAGS_x86_64_unknown_linux_gnu="-march=znver3 -mtune=znver3 -pipe"
    cargo_build "$@"
  )
}

# ==============================================================================
# Rust Crates (Full -O3 -march=znver3 -flto=thin C/C++ flags)
# ==============================================================================
dnf5 install -y \
  libxcb-devel \
  openssl-devel \
  dbus-devel \
  libsmbclient-devel \
  sqlite-devel \
  alsa-lib-devel \
  jack-audio-connection-kit-devel \
  libpcap-devel

for crate in \
  kmon \
  viddy \
  xan \
  doxx \
  xleak \
  croft-software \
  elio \
  termscp \
  papr-tui \
  wrkflw \
  serie \
  upmd \
  herdr \
  llmfit \
  reknife \
  edamame \
  llamastash; do
  cargo_build "${crate}"
done

# Crates pulling in aws-lc-sys / jitterentropy (avoids overriding crate's required -O0)
cargo_build_no_c_opt eilmeldung

# Git-sourced Rust tools (explicit --target so host build scripts stay safe)
cargo_build --git https://github.com/DingoOz/llm-visuals
cargo_build --git https://github.com/graiz/kittybrowser
cargo_build --git https://github.com/netop/netop || cargo_build --git https://github.com/DingoOz/netop || true
cargo_build --git https://gitlab.com/snipedbywifi/terminactory

# ALSA/JACK audio tool
cargo_build asak

# ==============================================================================
# Prebuilt Release Binaries (x86_64 Linux)
# ==============================================================================
curl -fsSL "https://github.com/allisonhere/tidemail/releases/latest/download/tidemail-linux-x86_64.tar.gz" -o "/tmp/tidemail.tar.gz"
tar xzf /tmp/tidemail.tar.gz -C /tmp/
cp /tmp/tidemail-linux-x86_64 /tmp/bin/tidemail
chmod +x /tmp/bin/tidemail

curl -fsSL "https://github.com/pulkitsharma07/solipsist/releases/latest/download/solipsist-linux-x64.tar.gz" -o "/tmp/solipsist.tar.gz"
tar xzf /tmp/solipsist.tar.gz -C /tmp/
cp /tmp/solipsist*/solipsist /tmp/bin/solipsist
chmod +x /tmp/bin/solipsist

curl -fsSL "https://github.com/errorware/crow/releases/latest/download/crow-linux-x86_64.tar.gz" -o "/tmp/crow.tar.gz"
tar xzf /tmp/crow.tar.gz -C /tmp/
cp /tmp/crow*/crow /tmp/bin/crow
chmod +x /tmp/bin/crow

curl -fsSL "https://corgi.computer/releases/20261106T233845Z-03c72b717526/corgi-linux-x86_64" -o "/tmp/bin/corgi"
chmod +x /tmp/bin/corgi

VERSION=$(curl -fsSL "https://github.com/vshvedov/rhun/releases/latest/download/VERSION" | tr -d ' \r\n')
curl -fsSL "https://github.com/vshvedov/rhun/releases/download/v${VERSION}/rhun-${VERSION}-linux-x86_64.tar.gz" -o "/tmp/rhun.tar.gz"
tar xzf /tmp/rhun.tar.gz -C /tmp
cp /tmp/rhun-${VERSION}/bin/rhun /tmp/bin/rhun
chmod +x /tmp/bin/rhun

# ==============================================================================
# Go Tools (GOAMD64=v3 for Zen 3 AVX2/FMA/BMI)
# ==============================================================================
export GOOS=linux
export GOARCH=amd64
export GOAMD64=v3
export CGO_ENABLED=0
export GOBIN=/tmp/bin

dnf5 install -y golang

go_build() {
  go install -trimpath -ldflags=-s -ldflags=-w "$@"
}

go_build github.com/szktkfm/mdtt/cmd/mdtt@latest
go_build github.com/termkit/gama@latest
go_build github.com/jesseduffield/lazygit@latest
go_build github.com/charmbracelet/glow/v2@latest
go_build github.com/chojs23/ec/cmd/ec@latest
go_build github.com/alvinunreal/lazyskills/cmd/lazyskills@latest
go_build github.com/edoardottt/cariddi/cmd/cariddi@latest
go_build github.com/yutat23/lsoff@latest
go_build github.com/Ri4dH/failtrace/cmd/failtrace@latest
go_build github.com/pedrosousa13/onda@latest
go_build github.com/halpworld/halpradio@latest

go clean -cache -modcache
