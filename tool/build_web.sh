#!/usr/bin/env bash
# Web 产线构建脚本（Cloudflare Pages 构建命令：bash tool/build_web.sh，
# 输出目录 build/web）。
#
# 品牌页外链通过环境变量注入（在 Pages 控制台 Settings → Environment
# variables 配置同名变量），此处透传为 --dart-define 编译进产物；
# 未设置的变量不注入，品牌页将隐藏对应入口，本地直接构建同样可用。
#
# Cloudflare Pages 构建机没有预装 Flutter：PATH 上找不到 flutter 时，
# 自动下载官方 Linux 稳定版发行包解压到 $HOME/flutter-sdk 并加入 PATH
# 再构建。默认钉住 3.44.6（与本地开发环境一致，满足 pubspec 的
# Dart ^3.12.2 约束），可用 FLUTTER_VERSION 环境变量覆盖。
set -euo pipefail

flutter_version="${FLUTTER_VERSION:-3.44.6}"
if ! command -v flutter >/dev/null 2>&1; then
  sdk_dir="$HOME/flutter-sdk"
  if [[ ! -x "$sdk_dir/bin/flutter" ]]; then
    tarball="flutter_linux_${flutter_version}-stable.tar.xz"
    url="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/$tarball"
    echo ">>> 未检测到 Flutter，开始下载稳定版 $flutter_version ..."
    rm -rf "$sdk_dir"
    mkdir -p "$sdk_dir"
    curl -fsSL --retry 3 -o "/tmp/$tarball" "$url"
    # 发行包顶层目录为 flutter/，剥掉一层直接铺进 sdk_dir，
    # 其内含已预缓存的 Dart SDK，无需 git 仓库即可运行。
    tar -xJf "/tmp/$tarball" -C "$sdk_dir" --strip-components=1
    rm -f "/tmp/$tarball"
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
