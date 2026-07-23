#!/usr/bin/env bash
# 一键安装本仓库的 git 钩子（当前仅 pre-commit：标签/分类 slug 冲突检查）。
# 用法：bash tools/install-hooks.sh
#
# 说明：本脚本把 tools/pre-commit 拷贝到 .git/hooks/，钩子更新后需重新运行。
# 更省心的替代方案（推荐）：直接让 git 使用 tools 目录作为钩子目录，
# 钩子改动即时同步、无需重装：
#     git config core.hooksPath tools
# 注意：git 不会克隆 .git/hooks 及 core.hooksPath 配置，任一方式在每个新克隆里都需执行一次。
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
hook_src="$repo_root/tools/pre-commit"
hook_dst="$repo_root/.git/hooks/pre-commit"

cp "$hook_src" "$hook_dst"
chmod +x "$hook_dst"
echo "✅ 已安装 pre-commit 钩子到 $hook_dst"
echo "   之后每次 git commit 前会自动运行 tools/check-tag-conflicts.rb。"
