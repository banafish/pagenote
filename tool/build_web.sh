#!/usr/bin/env bash
# Web 产线构建脚本（Cloudflare Pages 构建命令：bash tool/build_web.sh，
# 输出目录 build/web）。
#
# 品牌页外链通过环境变量注入（在 Pages 控制台 Settings → Environment
# variables 配置同名变量），此处透传为 --dart-define 编译进产物；
# 未设置的变量不注入，品牌页将隐藏对应入口，本地直接构建同样可用。
set -euo pipefail

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
