# 项目环境配置

本项目是使用 Jekyll 和 `jekyll-theme-chirpy` 构建的静态博客。项目的 GitHub Actions 使用 Ruby 3.1 构建，因此本地开发也应使用 Ruby 3.1。

## 前置条件

- macOS
- Git
- Xcode Command Line Tools
- Homebrew

可用以下命令确认基础工具已经安装：

```zsh
git --version
xcode-select -p
brew --version
```

若尚未安装 Xcode Command Line Tools，执行：

```zsh
xcode-select --install
```

## 安装 Ruby 3.1

不要直接使用系统 Ruby，也不要使用 Ruby 4.x 构建本项目。建议通过 `rbenv` 管理 Ruby 版本：

```zsh
brew install rbenv ruby-build
rbenv install 3.1.7
rbenv local 3.1.7
```

首次安装 `rbenv` 后，如果终端无法识别通过 rbenv 安装的 Ruby，请将以下配置加入 `~/.zshrc`，然后重新打开终端：

```zsh
eval "$(rbenv init - zsh)"
```

在仓库根目录确认版本：

```zsh
ruby --version
```

输出应为 `ruby 3.1.x`。

## 安装项目依赖

在仓库根目录执行：

```zsh
gem install bundler
bundle install
```

依赖由 `Gemfile` 管理。`Gemfile.lock` 是本地生成文件，已被 Git 忽略。

## 本地预览

启动带自动刷新的开发服务器：

```zsh
bundle exec jekyll serve --livereload
```

打开 <http://localhost:4000> 预览站点。停止服务可在终端按 `Ctrl-C`。

## 构建和检查

生成生产构建：

```zsh
JEKYLL_ENV=production bundle exec jekyll build
```

构建结果位于 `_site/`。提交前可执行标签和分类 slug 冲突检查：

```zsh
ruby tools/check-tag-conflicts.rb
```

也可安装仓库提供的 Git pre-commit 钩子，使该检查在每次提交前自动运行：

```zsh
bash tools/install-hooks.sh
```

## 不需要安装的环境

项目当前不包含 `package.json`，使用主题 Ruby Gem 提供前端资源。因此本地开发不需要安装 Node.js、npm、yarn、pnpm、数据库或 Docker。
