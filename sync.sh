#!/bin/bash

# 👇 在这里填入你的 Google Web 应用网址
GOOGLE_SCRIPT_URL="https://script.google.com/macros/s/AKfycbzIyWMn48MzkKE1HV1hJHqyoZUTJlxhfcJzkH6q_OPwXzlbZPqOKfr7064NE3VZo7tQ/exec"

if [[ "$GOOGLE_SCRIPT_URL" == *"你的ID"* ]]; then
  echo "请先在代码里配置 GOOGLE_SCRIPT_URL"
  exit 1
fi

echo "开始抓取 Issues..."

# 获取所有 open 状态的 issue（不依赖任何第三方库）
ISSUES=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/$GITHUB_REPOSITORY/issues?state=open&per_page=100")

# 解析出每一个 issue 的 number 和 title
NUMBERS=$(echo "$ISSUES" | jq -r '.[] | select(.title | contains("[上传记录]")) | .number')

for NUM in $NUMBERS; do
  echo "处理 Issue #$NUM"
  
  # 获取单个 Issue 详情
  ISSUE_DETAIL=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$NUM")
  
  # 检查是否已经带有"已同步"标签
  SYNCED=$(echo "$ISSUE_DETAIL" | jq -r '.labels[].name' | grep -c "已同步")
  if [ "$SYNCED" -gt 0 ]; then
    echo "  Issue #$NUM 已同步，跳过。"
    continue
  fi

  BODY=$(echo "$ISSUE_DETAIL" | jq -r '.body')
  
  # 提取字段
  EMP_ID=$(echo "$BODY" | grep "\*\*工号\*\*:" | sed 's/\*\*工号\*\*: //')
  TYPE=$(echo "$BODY" | grep "\*\*类型\*\*:" | sed 's/\*\*类型\*\*: //')
  TIME=$(echo "$BODY" | grep "\*\*时间\*\*:" | sed 's/\*\*时间\*\*: //')
  IMG_URL=$(echo "$BODY" | grep -o 'https://[^)]*' | head -n 1)

  # 拼装 JSON（使用 jq 防止特殊字符转义错误）
  JSON_DATA=$(jq -n \
    --arg id "$EMP_ID" \
    --arg type "$TYPE" \
    --arg url "$IMG_URL" \
    --arg time "$TIME" \
    '{employeeId: $id, type: $type, imageUrl: $url, uploadTime: $time}')

  # 发送给 Google
  echo "  发送数据: $JSON_DATA"
  curl -s -X POST -H "Content-Type: application/json" -d "$JSON_DATA" "$GOOGLE_SCRIPT_URL"

  # 添加"已同步"标签
  curl -s -X POST -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    -d '{"labels":["已同步"]}' \
    "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$NUM/labels" > /dev/null
    
  echo "  Issue #$NUM 同步完成。"
done

echo "所有同步任务结束！"
