# Git & GitHub + Worktree + TDD 快速参考

**用途**: 日常速查，快速查找命令
**格式**: 命令 + 用途 + 注意事项

---

## GitHub 初始化

| 任务 | 命令 | 说明 |
|------|:---|---|
| 创建 GitHub 仓库 | https://github.com/new | 浏览器打开，不勾选 Initialize |
| 获取 HTTPS URL | 仓库页面右上 Code 按钮 | 复制 HTTPS 地址 |
| 生成 Token | https://github.com/settings/tokens | Generate new token (classic) → 选 repo scope |

---

## 本地 Git 配置

| 任务 | 命令 |
|------|:---|
| 初始化仓库 | `git init` |
| 查看状态 | `git status` |
| 配置用户名 | `git config user.name "Your Name"` |
| 配置邮箱 | `git config user.email "you@example.com"` |
| 创建 .gitignore | `cat > .gitignore << 'EOF'` + 内容 + `EOF` |
| 添加所有文件 | `git add .` |
| 提交 | `git commit -m "Initial commit"` |
| 查看历史 | `git log --oneline` |

---

## GitHub 连接与推送

| 任务 | 命令 | 前提 |
|------|:---|---|
| 添加远程仓库 | `git remote add origin URL` | 替换 URL |
| 查看远程配置 | `git remote -v` | 验证连接 |
| 推送（用 Token） | `git remote set-url origin "https://user:TOKEN@github.com/user/repo.git"` | Token 必须有效 |
| 推送代码 | `git push -u origin main` | 第一次推送用 `-u` |
| 删除 URL 中的 Token | `git remote set-url origin "https://github.com/user/repo.git"` | **推送后必做** |

---

## Git Worktree（隔离开发）

| 任务 | 命令 | 说明 |
|------|:---|---|
| 创建 worktree | `git worktree add ../task-name -b feature/task-name main` | 基于 main 创建新分支 |
| 进入 worktree | `cd ../task-name` | 进入隔离目录 |
| 查看所有 worktree | `git worktree list` | 列出活跃的 worktree |
| 删除 worktree | `git worktree remove ../task-name` | 任务完成后清理 |

---

## TDD 工作流（RED-GREEN-REFACTOR）

### RED 阶段（写 Failing Test）

```javascript
// test.js - 测试先行，实现还没有
function testAdd() {
  const result = add(2, 3);
  console.assert(result === 5, "Expected 5");
}

testAdd();  // 此时会报错：add is not defined
```

**命令**：
```bash
node test.js  # 预期：❌ FAILED
```

---

### GREEN 阶段（最小实现）

```javascript
// test.js - 加入实现
function add(a, b) {
  return a + b;
}

function testAdd() {
  const result = add(2, 3);
  console.assert(result === 5, "Expected 5");
  console.log("✅ PASSED");
}

testAdd();  # 预期：✅ PASSED
```

**命令**：
```bash
node test.js  # 预期：✅ PASSED
```

---

### REFACTOR 阶段（优化，但保持 GREEN）

```javascript
// test.js - 改进代码（算法 / 可读性 / 效率）
// 但逻辑不变，测试还是通过
```

**命令**：
```bash
node test.js  # 预期：✅ PASSED（必须保持）
```

---

## 提交与合并

| 任务 | 命令 |
|------|:---|
| 添加改动 | `git add .` |
| 提交 | `git commit -m "feat: describe change"` |
| 查看分支差异 | `git diff main feature/branch --stat` |
| 切换分支 | `git checkout main` |
| 合并分支 | `git merge feature/branch` |
| 删除分支 | `git branch -d feature/branch` |

---

## 查看历史与同步

| 任务 | 命令 |
|------|:---|
| 查看本地历史 | `git log --oneline -5` |
| 查看远程历史 | `git log origin/main --oneline -5` |
| 更新本地（拉取远程） | `git pull origin main` |
| 推送到远程 | `git push origin main` |
| 强制同步（危险） | `git reset --hard origin/main` |

---

## 常见问题速查

### Q: Token 过期了怎么办？
```bash
# 重新生成 Token
https://github.com/settings/tokens

# 用新 Token 更新
git remote set-url origin "https://user:NEW_TOKEN@github.com/user/repo.git"
git push origin main

# 删除 Token（安全）
git remote set-url origin "https://github.com/user/repo.git"
```

### Q: 推送时 403 Forbidden？
```bash
# 检查 Token 有效性
curl -H "Authorization: token YOUR_TOKEN" https://api.github.com/user

# 如果失败，重新生成 Token 并更新 URL
```

### Q: Worktree 创建失败（分支已被使用）？
```bash
# 确保分支名唯一
git branch -a  # 查看所有分支

# 创建时用新分支名
git worktree add ../new-task -b feature/new-task main
```

### Q: 不小心提交了 .DS_Store？
```bash
# 从 git 中删除（不删除本地文件）
git rm --cached .DS_Store

# 添加 .gitignore
git add .gitignore

# 新提交
git commit -m "Remove .DS_Store and add .gitignore"
```

### Q: 想删除某个本地提交？
```bash
# 查看历史
git log --oneline

# 重置到之前的提交（保留改动）
git reset --soft HEAD~1

# 或者硬重置（删除改动）
git reset --hard HEAD~1
```

---

## 工作流速记

### 完整任务流程（一键速查）

```bash
# 1. 创建 Worktree
git worktree add ../task-001 -b feature/task-001 main
cd ../task-001

# 2. 写 Failing Test
cat > test.js << 'EOF'
function test() { /* ... */ }
test();  // 预期失败
EOF
node test.js

# 3. 最小实现（让测试通过）
# 编辑 test.js，加入实现
node test.js  # 验证通过

# 4. 提交
git add .
git commit -m "feat: implement feature"

# 5. 回到主分支
cd ../coding\ repo.
git checkout main

# 6. Review
git diff main feature/task-001

# 7. Merge
git merge feature/task-001

# 8. 推送
git push origin main

# 9. 清理
git worktree remove ../task-001
```

---

## Git 配置（可选但推荐）

```bash
# 全局配置用户信息
git config --global user.name "Your Name"
git config --global user.email "your@email.com"

# 设置默认编辑器
git config --global core.editor "vim"

# 设置彩色输出
git config --global color.ui true

# 查看当前配置
git config --list
```

---

## 文件状态流转图

```
新建文件
  ↓
Untracked（git 没见过）
  ↓ git add
Staged（标记为待提交）
  ↓ git commit
Committed（保存在本地 git 历史）
  ↓ git push
Remote（推送到 GitHub）
```

---

## 提交信息规范

```bash
# 好的提交信息
git commit -m "feat: add user authentication"
git commit -m "fix: resolve memory leak in parser"
git commit -m "refactor: simplify calculation logic"
git commit -m "docs: update README with installation steps"

# 格式：<type>(<scope>): <subject>
# type 可以是：feat, fix, docs, style, refactor, perf, test, chore
```

