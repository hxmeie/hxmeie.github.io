#!/usr/bin/env bash
# 一键安装本仓库的 git 钩子（当前仅 pre-commit：标签/分类 slug 冲突检查）。
# 用法：bash tools/install-hooks.sh
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
hook_src="$repo_root/tools/pre-commit"
hook_dst="$repo_root/.git/hooks/pre-commit"

cp "$hook_src" "$hook_dst"
chmod +x "$hook_dst"
echo "✅ 已安装 pre-commit 钩子到 $hook_dst"
echo "   之后每次 git commit 前会自动运行 tools/check-tag-conflicts.rb。"
