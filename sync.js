const { Octokit } = require("@octokit/rest");

const octokit = new Octokit({ auth: process.env.GITHUB_TOKEN });
const repo = process.env.GITHUB_REPOSITORY.split('/');
const owner = repo[0];
const repoName = repo[1];
const GOOGLE_SCRIPT_URL = process.env.GOOGLE_SCRIPT_URL;

async function sync() {
  if (!GOOGLE_SCRIPT_URL) {
    console.error("未配置 GOOGLE_SCRIPT_URL");
    return;
  }

  console.log("开始抓取 Issues...");
  // 抓取所有处于 open 状态且不带“已同步”标签的 Issue
  const issues = await octokit.issues.listForRepo({
    owner, repo: repoName, state: 'open', labels: '待同步'
  });

  // 注意：如果没有加标签，上面那行可能抓不到，为了容错，我们先自动给没有标签的加“待同步”
  // 但最简单的办法是直接抓最近的所有 open Issue，在正文里过滤。
  // 为了简化，这里抓取所有 open 状态的，并在本地过滤掉带有“已同步”标签的。
  
  const allOpenIssues = await octokit.issues.listForRepo({
    owner, repo: repoName, state: 'open', per_page: 100
  });

  for (const issue of allOpenIssues.data) {
    // 如果已经同步过，跳过
    if (issue.labels.some(l => l.name === '已同步')) continue;
    // 如果不是我们前端发的记录，跳过
    if (!issue.title.includes('[上传记录]')) continue;

    console.log(`发现新记录: ${issue.title}`);
    const body = issue.body;

    // 从 Issue 正文中解析出四个字段（正则匹配）
    const idMatch = body.match(/\*\*工号\*\*: (.*)/);
    const typeMatch = body.match(/\*\*类型\*\*: (.*)/);
    const timeMatch = body.match(/\*\*时间\*\*: (.*)/);
    const urlMatch = body.match(/\[点击查看原图\]\((.*?)\)/);

    const data = {
      employeeId: idMatch ? idMatch[1].trim() : "未知",
      type: typeMatch ? typeMatch[1].trim() : "未知",
      uploadTime: timeMatch ? timeMatch[1].trim() : "未知",
      imageUrl: urlMatch ? urlMatch[1].trim() : ""
    };

    // 发给 Google Apps Script
    try {
      await fetch(GOOGLE_SCRIPT_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(data)
      });

      // 同步成功后，给 Issue 打上“已同步”标签，防止重复抓取
      await octokit.issues.addLabels({
        owner, repo: repoName, issue_number: issue.number, labels: ['已同步']
      });
      console.log(`同步成功: ${issue.title}`);
    } catch (err) {
      console.error(`同步失败: ${issue.title}`, err);
    }
  }
}

sync();
