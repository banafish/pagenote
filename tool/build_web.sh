#!/usr/bin/env bash
# Web 产线构建脚本（Cloudflare Pages 构建命令：bash tool/build_web.sh，
# 输出目录 build/web）。
#
# 品牌页外链通过环境变量注入（在 Pages 控制台 Settings → Environment
# variables 配置同名变量），此处透传为 --dart-define 编译进产物；
# 未设置的变量不注入，品牌页将隐藏对应入口，本地直接构建同样可用。
#
# Cloudflare Pages 构建机没有预装 Flutter：PATH 上找不到 flutter 时，
# 自动探测可用镜像源后下载官方 Linux 稳定版发行包，解压到
# $HOME/flutter-sdk 并加入 PATH 再构建。默认钉住 3.44.6（与本地开发
# 环境一致，满足 pubspec 的 Dart ^3.12.2 约束），可用 FLUTTER_VERSION
# 覆盖版本、FLUTTER_STORAGE_BASE_URL 指定镜像源。
set -euo pipefail

flutter_version="${FLUTTER_VERSION:-3.44.6}"
if ! command -v flutter >/dev/null 2>&1; then
  sdk_dir="$HOME/flutter-sdk"
  if [[ ! -x "$sdk_dir/bin/flutter" ]]; then
    # Cloudflare Pages 构建机访问 storage.googleapis.com 曾返回 403：
    # 依次探测各镜像源的 releases 元数据，取第一个可达者下载，并把
    # 该源导出为 FLUTTER_STORAGE_BASE_URL，使构建期补拉 Web SDK 等
    # 产物同样走可达源。用户显式配置的源排最前。
    storage_bases=(
      https://storage.googleapis.com
      https://storage.flutter-io.cn
    )
    if [[ -n "${FLUTTER_STORAGE_BASE_URL:-}" ]]; then
      storage_bases=("$FLUTTER_STORAGE_BASE_URL" "${storage_bases[@]}")
    fi
    mirror=""
    for base in "${storage_bases[@]}"; do
      base="${base%/}"
      echo ">>> 探测 Flutter 镜像源 $base ..."
      if curl -fsI --max-time 8 "$base/flutter_infra_release/releases/releases_linux.json" >/dev/null 2>&1; then
        mirror="$base"
        break
      fi
    done
    if [[ -z "$mirror" ]]; then
      echo ">>> 所有镜像源均不可达，可在 Pages 环境变量里设置 FLUTTER_STORAGE_BASE_URL 指定镜像后重试。" >&2
      exit 1
    fi
    echo ">>> 未检测到 Flutter，从 $mirror 下载稳定版 $flutter_version ..."
    rm -rf "$sdk_dir"
    mkdir -p "$sdk_dir"
    tarball="flutter_linux_${flutter_version}-stable.tar.xz"
    curl -fsSL --retry 3 -o "/tmp/$tarball" \
      "$mirror/flutter_infra_release/releases/stable/linux/$tarball"
    # 发行包顶层目录为 flutter/，剥掉一层直接铺进 sdk_dir，
    # 其内含已预缓存的 Dart SDK，无需 git 仓库即可运行。
    tar -xJf "/tmp/$tarball" -C "$sdk_dir" --strip-components=1
    rm -f "/tmp/$tarball"
    export FLUTTER_STORAGE_BASE_URL="$mirror"
  fi
  export PATH="$sdk_dir/bin:$PATH"
  # CI 上避免首跑的遥测提示干扰日志；失败不影响构建。
  flutter config --no-analytics >/dev/null 2>&1 || true
fi

defines=()
add_define() { # <dart-define 键> <同名环境变量>
  local value="${!1:-}"
  if [[ -n "$value" ]]; then
    defines+=("--dart-define=$1=$value")
  fi
}

add_define PAGENOTE_GITHUB_REPO
add_define PAGENOTE_GITHUB_RELEASES
add_define PAGENOTE_DOWNLOAD_ANDROID
add_define PAGENOTE_DOWNLOAD_PC

# bash 3.2（macOS 自带）下空数组 + set -u 会报错，用条件展开兜底。
flutter build web --release "${defines[@]+${defines[@]}}"
