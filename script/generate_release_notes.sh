#!/usr/bin/env bash

set -euo pipefail

TAG="${1:?Usage: generate_release_notes.sh <tag> <output-file> <repository-url>}"
OUTPUT_FILE="${2:?Usage: generate_release_notes.sh <tag> <output-file> <repository-url>}"
REPOSITORY_URL="${3:?Usage: generate_release_notes.sh <tag> <output-file> <repository-url>}"
HIGHLIGHTS="${RELEASE_HIGHLIGHTS:-}"

if [[ ! "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z.-]*)?$ ]]; then
  echo "Invalid tag: $TAG" >&2
  exit 1
fi

if [[ -z "$(printf '%s' "$HIGHLIGHTS" | tr -d '[:space:]|')" ]]; then
  echo "RELEASE_HIGHLIGHTS must contain at least one user-facing change." >&2
  exit 1
fi

target_ref="HEAD"
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  target_ref="$TAG"
fi
previous_tag="$(git describe --tags --match 'v[0-9]*' --abbrev=0 "$target_ref^" 2>/dev/null || true)"

if [[ -n "$previous_tag" ]]; then
  changelog_url="$REPOSITORY_URL/compare/$previous_tag...$TAG"
  changelog_label="查看 $previous_tag 到 $TAG 的完整变更"
else
  changelog_url="$REPOSITORY_URL/commits/$TAG"
  changelog_label="查看 $TAG 的完整提交记录"
fi

mkdir -p "$(dirname "$OUTPUT_FILE")"

{
  printf '## 本版本更新\n\n'

  normalized_highlights="${HIGHLIGHTS//|/$'\n'}"
  while IFS= read -r highlight || [[ -n "$highlight" ]]; do
    highlight="$(printf '%s' "$highlight" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    highlight="${highlight#- }"
    if [[ -n "$highlight" ]]; then
      printf -- '- %s\n' "$highlight"
    fi
  done < <(printf '%s' "$normalized_highlights")

  cat <<EOF

## 下载与安装

1. 在下方 **Assets** 下载 \`SpendScope-macOS-unsigned.dmg\`。
2. 打开 DMG，将 SpendScope 拖入“应用程序”文件夹。
3. 首次启动请在 Finder 中右键 SpendScope，选择“打开”，再确认一次。

## 系统与芯片支持

- macOS 14 或更高版本。
- Universal Binary，同时支持 Apple 芯片（arm64）和 Intel 芯片（x86_64）。

## 未签名版本首次打开

当前安装包尚未使用 Apple Developer ID 签名和公证。若系统提示应用“已损坏”，请先确认 DMG 来自本仓库的 GitHub Releases，再在终端执行：

\`\`\`bash
xattr -dr com.apple.quarantine /Applications/SpendScope.app
\`\`\`

不要对来源不明的 App 执行此命令。

## 附件说明

- \`SpendScope-macOS-unsigned.dmg\`：macOS 安装包。
- \`SpendScope-macOS-unsigned.dmg.sha256\`：安装包 SHA-256 校验文件。
- \`Source code (zip)\` / \`Source code (tar.gz)\`：GitHub 根据本版本标签自动生成的源码包。

下载 DMG 和校验文件后，可在同一目录执行：

\`\`\`bash
shasum -a 256 -c SpendScope-macOS-unsigned.dmg.sha256
\`\`\`

## 已知限制

- 当前安装包未签名、未公证，首次启动需要手动确认。
- SpendScope 仅统计本机 Codex 记录，不同步其他设备或服务端历史。
- 模型费用仅为 API 标准价下的等值估算，不代表 Codex 实际账单；暂不提供账单对账或 API Key 实际消费分析。

## 完整变更

[$changelog_label]($changelog_url)
EOF
} > "$OUTPUT_FILE"
