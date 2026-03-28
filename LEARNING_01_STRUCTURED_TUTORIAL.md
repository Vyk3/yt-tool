# Git & GitHub + Superpowers + PUA 结构化教程

**日期**: 2026-03-28 ~ 2026-03-29
**目标**: 从零搭建 GitHub 仓库 → Worktree 隔离 → TDD 工作流
**难度**: ⭐⭐⭐ 中等

---

## 第一部分：GitHub 仓库创建与认证

### 步骤 1.1：在 GitHub 创建仓库

**在浏览器中操作：**
1. 打开 https://github.com/new
2. 填写表单：
   - **Repository name**: `coding-repo` 或你喜欢的名字
   - **Description**: 可选，随意填
   - **Public/Private**: 根据需要选择
3. **不要勾选** "Initialize this repository with README"（本地已有代码）
4. 点 **Create repository**
5. 跳转后会看到初始化命令，**复制 HTTPS URL**：
   ```
   https://github.com/你的用户名/你的仓库名.git
   ```

### 步骤 1.2：在本地初始化 Git

**在终端中操作：**

```bash
# 进入项目目录
cd ~/Desktop/coding\ repo.

# 初始化 git（如果还没有）
git init

# 查看当前状态
git status
```

**预期输出：**
```
On branch main
No commits yet
Untracked files:
  (use "git add <file>..." to include in what will be committed)
        .DS_Store
        CLAUDE.md
        ...
```

### 步骤 1.3：创建 .gitignore（防止污染）

**问题**：`.DS_Store` 是 Mac 系统文件，不应该提交。

**解决方案**：

```bash
cat > .gitignore << 'EOF'
.DS_Store
.DS_Store?
*.swp
*.swo
.env
node_modules/
EOF
```

验证：
```bash
cat .gitignore
```

### 步骤 1.4：第一次提交

```bash
# 添加文件到 staging 区域
git add .

# 提交
git commit -m "Initial commit: add CLAUDE.md and project config"

# 查看历史
git log --oneline
```

**预期输出：**
```
abc1234 Initial commit: add CLAUDE.md and project config
```

### 步骤 1.5：关联 GitHub 远程仓库

```bash
# 添加远程仓库
git remote add origin https://github.com/你的用户名/你的仓库名.git

# 验证
git remote -v
```

**预期输出：**
```
origin  https://github.com/你的用户名/你的仓库名.git (fetch)
origin  https://github.com/你的用户名/你的仓库名.git (push)
```

### 步骤 1.6：生成 Personal Access Token（认证）

**在浏览器中操作：**
1. 打开 https://github.com/settings/tokens
2. 点 **"Generate new token (classic)"**
3. 填写：
   - **Token name**: `coding-repo-token`
   - **Expiration**: 90 days
   - **Scopes**: 勾选 `repo`（完整仓库权限）
4. 点 **Generate token**
5. **复制 token**（`ghp_` 开头的长字符串）

### 步骤 1.7：推送到 GitHub

```bash
# 使用 token 推送（替换 TOKEN）
git remote set-url origin "https://你的用户名:TOKEN@github.com/你的用户名/你的仓库名.git"

# 推送
git push -u origin main

# 立即删除 URL 中的 token（安全）
git remote set-url origin "https://github.com/你的用户名/你的仓库名.git"

# 验证
git remote -v
```

**预期输出：**
```
To https://github.com/你的用户名/你的仓库名.git
 * [new branch]      main -> main
branch 'main' set up to track 'origin/main'.
```

---

## 第二部分：Git Worktree 隔离开发

### 步骤 2.1：理解 Worktree 的用途

**问题**：
- 在主分支上直接改代码 → 失败了污染主分支
- 新分支和主分支共享工作目录 → 改了文件不知道是哪个分支的

**解决方案**：
- **Worktree** = 独立的工作目录 + 独立的分支
- 每个任务有自己的目录和分支，互不影响

### 步骤 2.2：创建 Worktree

```bash
# 在项目目录下，创建新 worktree
# 基于 main 分支，创建 feature/task-001 分支
git worktree add ../coding-task-001 -b feature/task-001 main

# 验证
git worktree list
```

**预期输出：**
```
/Users/koa/Desktop/coding repo.         abc1234 [main]
/Users/koa/Desktop/coding-task-001      abc1234 [feature/task-001]
```

### 步骤 2.3：进入 Worktree 开始工作

```bash
cd /Users/koa/Desktop/coding-task-001

# 验证分支
git status
git branch
```

**预期输出：**
```
On branch feature/task-001
nothing to commit, working tree clean
```

---

## 第三部分：TDD 工作流（RED-GREEN-REFACTOR）

### 步骤 3.1：RED - 写一个 Failing Test

**创建 test-example.js：**

```bash
cat > test-example.js << 'EOF'
// RED 阶段：写一个必然失败的测试
function testCalculateSum() {
  const result = calculateSum(2, 3);
  console.assert(result === 5, `Expected 5 but got ${result}`);
  console.log("✅ Test passed: calculateSum(2, 3) = 5");
}

function testCalculateSumWithNegative() {
  const result = calculateSum(-1, 3);
  console.assert(result === 2, `Expected 2 but got ${result}`);
  console.log("✅ Test passed: calculateSum(-1, 3) = 2");
}

// 运行测试
try {
  testCalculateSum();
  testCalculateSumWithNegative();
} catch (e) {
  console.error("❌ Test failed:", e.message);
}
EOF
```

**运行测试（看它失败）：**

```bash
node test-example.js
```

**预期输出：**
```
❌ Test failed: calculateSum is not defined
```

### 步骤 3.2：GREEN - 写最小实现

**修改 test-example.js（加入实现）：**

```bash
cat > test-example.js << 'EOF'
// GREEN 阶段：最小实现让测试通过
function calculateSum(a, b) {
  return a + b;
}

function testCalculateSum() {
  const result = calculateSum(2, 3);
  console.assert(result === 5, `Expected 5 but got ${result}`);
  console.log("✅ Test passed: calculateSum(2, 3) = 5");
}

function testCalculateSumWithNegative() {
  const result = calculateSum(-1, 3);
  console.assert(result === 2, `Expected 2 but got ${result}`);
  console.log("✅ Test passed: calculateSum(-1, 3) = 2");
}

// 运行测试
testCalculateSum();
testCalculateSumWithNegative();
EOF
```

**运行测试（看它通过）：**

```bash
node test-example.js
```

**预期输出：**
```
✅ Test passed: calculateSum(2, 3) = 5
✅ Test passed: calculateSum(-1, 3) = 2
```

### 步骤 3.3：REFACTOR - 优化代码（可选）

在本例中实现已经很简洁，无需进一步优化。但在实际项目中，你会在这步：
- 添加错误处理
- 优化算法效率
- 改进代码可读性

**重点**：改了任何东西，必须重新运行测试确保还是 GREEN。

### 步骤 3.4：提交到分支

```bash
git add test-example.js

git commit -m "feat: implement calculateSum with TDD (RED-GREEN-REFACTOR)"

git log --oneline -2
```

**预期输出：**
```
abc1234 feat: implement calculateSum with TDD (RED-GREEN-REFACTOR)
def5678 Initial commit
```

---

## 第四部分：Code Review + Merge 回主分支

### 步骤 4.1：Code Review（对标规格）

**回到主分支，审查改动：**

```bash
cd /Users/koa/Desktop/coding\ repo.

git diff main feature/task-001 --stat
```

**预期输出：**
```
 test-example.js | 20 ++++++++++++++++++++
 1 file changed, 20 insertions(+)
```

**问题清单**：
- [ ] 改动符合规格吗？
- [ ] 所有测试都通过了吗？
- [ ] 代码风格一致吗？
- [ ] 有新增的 bug 吗？

### 步骤 4.2：Merge 回主分支

```bash
# 切回 main
git checkout main

# Merge
git merge feature/task-001

git log --oneline -3
```

**预期输出：**
```
abc1234 feat: implement calculateSum with TDD (RED-GREEN-REFACTOR)
def5678 Initial commit
...
```

### 步骤 4.3：推送到 GitHub

```bash
git push origin main

# 验证
git log --oneline origin/main -2
```

**预期输出：**
```
abc1234 feat: implement calculateSum with TDD (RED-GREEN-REFACTOR)
def5678 Initial commit
```

---

## 第五部分：清理 Worktree

### 步骤 5.1：任务完成后清理

```bash
# 删除 worktree
git worktree remove ../coding-task-001

# 验证
git worktree list
```

**预期输出：**
```
/Users/koa/Desktop/coding repo.  abc1234 [main]
```

---

## 完整流程检查清单

- [ ] GitHub 仓库已创建
- [ ] 本地 git 初始化 & .gitignore 配置
- [ ] 第一次 commit 已推送到 GitHub
- [ ] Personal Access Token 已生成
- [ ] Worktree 创建、使用、清理流程已演练
- [ ] TDD RED-GREEN-REFACTOR 循环已完成
- [ ] Code Review 对标规格已进行
- [ ] Merge 和推送已完成
- [ ] Token 已从 URL 中删除（安全）

---

## 核心要点总结

| 阶段 | 命令 | 目的 |
|------|:---|---|
| **初始化** | `git init` | 本地仓库初始化 |
| **配置** | `git config` | 用户信息配置 |
| **.gitignore** | `git add .gitignore` | 排除系统文件 |
| **提交** | `git commit -m "msg"` | 保存当前状态 |
| **关联** | `git remote add origin URL` | 连接 GitHub |
| **认证** | Personal Access Token | HTTPS 推送认证 |
| **Worktree** | `git worktree add path -b branch` | 隔离开发环境 |
| **TDD** | RED → GREEN → REFACTOR | 测试驱动开发 |
| **Review** | `git diff main feature/branch` | 代码审查 |
| **Merge** | `git merge branch` | 合并分支 |
| **推送** | `git push origin main` | 同步到 GitHub |

