#!/usr/bin/env ruby
# frozen_string_literal: true

# 检查 _posts 下所有文章的 tags/categories 是否存在“同名不同大小写/同 slug”冲突。
# 例如 tag `android` 与 `Android` 都会被 Jekyll 生成到 /tags/android/，
# 导致构建时 "Conflict: destination shared by multiple files" 警告并覆盖页面。
# 该脚本在检测到冲突时以退出码 1 结束，可用于 CI 或 git pre-commit 钩子拦截。
#
# Detect tag/category slug collisions (e.g. `android` vs `Android`) in _posts
# before Jekyll build. Exits with status 1 when any collision is found.

require 'yaml'
require 'set'
require 'date'

POSTS_DIR = File.expand_path('../_posts', __dir__)

# 复刻 Jekyll 默认 slugify：转小写，非字母数字（含中文）序列替换为连字符，去除首尾连字符。
# Replicate Jekyll's default slugify used for tag/category permalinks.
# @param value 原始标签或分类字符串
# @return String 归一化后的 slug
def slugify(value)
  value.to_s.downcase.gsub(/[^\p{Alnum}]+/u, '-').gsub(/\A-+|-+\z/, '')
end

# 从单个 Markdown 文件中解析 YAML front matter。
# Parse the YAML front matter block from one markdown post.
# @param path 文章文件路径
# @return Hash 解析出的 front matter（无则返回空 Hash）
def front_matter(path)
  content = File.read(path, encoding: 'utf-8')
  return {} unless content.start_with?('---')

  _, fm, = content.split(/^---\s*$\n/, 3)
  # front matter 里 date 字段是时间类型，需允许 Time/Date 才能解析
  fm ? (YAML.safe_load(fm, permitted_classes: [Time, Date], aliases: true) || {}) : {}
rescue StandardError => e
  warn "  跳过（front matter 解析失败）: #{path} -> #{e.message}"
  {}
end

# key: 归一化 slug -> value: { 原始写法 => [出现的文件相对路径, ...] }
# 分别按 tags 与 categories 两个命名空间统计（二者互不冲突）。
groups = { 'tags' => Hash.new { |h, k| h[k] = Hash.new { |hh, kk| hh[kk] = [] } },
           'categories' => Hash.new { |h, k| h[k] = Hash.new { |hh, kk| hh[kk] = [] } } }

Dir.glob(File.join(POSTS_DIR, '*.md')).sort.each do |path|
  fm = front_matter(path)
  rel = path.sub("#{File.dirname(POSTS_DIR)}/", '')

  %w[tags categories].each do |field|
    Array(fm[field]).each do |raw|
      next if raw.nil? || raw.to_s.strip.empty?

      groups[field][slugify(raw)][raw.to_s] << rel
    end
  end
end

conflicts = []
groups.each do |field, slugs|
  slugs.each do |slug, variants|
    next if variants.size <= 1 # 只有一种写法，不冲突 / single spelling, no clash

    conflicts << [field, slug, variants]
  end
end

if conflicts.empty?
  puts '✅ 标签/分类检查通过：未发现同 slug 冲突。'
  exit 0
end

warn '❌ 发现标签/分类 slug 冲突（同一 slug 存在多种写法，会导致 Jekyll 构建覆盖页面）:'
conflicts.each do |field, slug, variants|
  warn ''
  warn "  [#{field}] slug = \"#{slug}\" 存在 #{variants.size} 种写法:"
  variants.each do |raw, files|
    warn "    - \"#{raw}\"  →  #{files.join(', ')}"
  end
end
warn ''
warn '  修复方式：把这些写法统一成同一种（本项目约定标签一律小写）。'
exit 1
