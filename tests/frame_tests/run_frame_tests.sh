#!/usr/bin/env bash
# 2ndFight Frame Tests — Stage 0 安全網
#
# 用法:
#   bash tests/frame_tests/run_frame_tests.sh
#
# 環境:
#   - 需要 Godot 4.6.x CLI（專案 config/features = "4.6"）
#   - 若 godot 不在 PATH，用 GODOT_BIN 指定:
#     GODOT_BIN=/path/to/godot bash tests/frame_tests/run_frame_tests.sh
#
# 退出碼: 0 = 全部通過, 1 = 有用例失敗

set -euo pipefail
cd "$(dirname "$0")/../.."

GODOT="${GODOT_BIN:-godot}"
exec "$GODOT" --headless --path . -s res://tests/frame_tests/run_tests.gd
