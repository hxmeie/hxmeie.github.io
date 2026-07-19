# Repository Instructions

This file contains the project rules for all coding agents working in this repository.

## What This Is

A personal Jekyll blog (哆啦A梦小短腿 / hxmeie) built on the [jekyll-theme-chirpy](https://github.com/cotes2020/jekyll-theme-chirpy) gem (v7.6.0, pulled in as a dependency via `Gemfile`, not forked into the repository). It is deployed to GitHub Pages by GitHub Actions on every push to `master`. Content is almost entirely Chinese-language Android/Kotlin technical notes and interview preparation.

Because the theme is consumed as a gem rather than forked, this repository only contains site-specific content and overrides. There is no theme source code, no `assets/js` build pipeline, and no `package.json` to maintain here.

## Commands

```bash
bundle install                              # Install Ruby dependencies (first-time setup)
bundle exec jekyll serve                    # Local dev server with live rebuild: http://localhost:4000
bundle exec jekyll build                    # Production build to ./_site
JEKYLL_ENV=production bundle exec jekyll build --baseurl ""   # Mirror the CI build
ruby tools/check-tag-conflicts.rb           # Check tag/category slug conflicts
```

The project has no test suite, linter, or single-file test runner. `html-proofer` is present in the `Gemfile` `:test` group but is not wired into a script. Validate changes by building the site and, when relevant, running `jekyll serve` and checking the affected page in a browser.

Deployment is automatic: pushing to `master` triggers `.github/workflows/jekyll.yml`, which builds with Jekyll and deploys `_site` to GitHub Pages. There is no manual deployment step. CI uses Ruby 3.1; use Ruby 3.1 locally as documented in `docs/environment-setup.md`.

## Structure And Conventions

- `_posts/`: Blog posts with standard Jekyll `YYYY-MM-DD-title.md` filenames. Use the existing frontmatter shape:

  ```yaml
  categories: [分类1, 分类2]
  title: 标题
  date: 2023-05-19 13:28:00 +0800
  tags: [标签1, 标签2]
  keywords: [关键词1, 关键词2]
  image:
    path: <cover image URL>
    lqip: /assets/img/placeholder.webp
    alt: image description
  ```

  Tags must be lowercase (for example, `flutter`, `dart`, `channel`; never `Flutter` or `Dart`). Chirpy generates one case-sensitive tag page per exact tag string. Chinese tags are unaffected. Categories follow the existing capitalized convention, such as `Flutter`.

  The `date` must be the real creation time and must not be in the future. Obtain it from the current wall clock with `date "+%Y-%m-%d %H:%M:%S %z"`; do not guess or round it. Jekyll defaults to `future: false`, so a future-dated post is silently excluded from builds until that time.

  Do not manually add `last_modified_at`. `_plugins/posts-lastmod-hook.rb` derives it from each post file's Git commit history during builds.

- `_tabs/`: Top-level navigation pages, rendered through the `tabs` collection in `_config.yml`.
- `_data/`: Small YAML overrides consumed by the theme, such as `contact.yml` and `share.yml`.
- `_plugins/`: Repository-local Jekyll plugins and hooks.
- `_config.yml`: Site configuration, including Giscus, PWA cache, pagination, permalink structure, and Jekyll exclusions. Do not change the `/posts/:title/` permalink structure without updating existing post links.
- `assets/`: Static assets and self-hosted images/media.
- `CNAME`: Custom GitHub Pages domain.
- `_site/` and `.jekyll-cache/`: Generated output. They are ignored by Git and must not be edited directly.

## Working With Posts

When adding or editing a post, match frontmatter in recent files under `_posts/`; do not invent a new schema. Filenames must preserve the `YYYY-MM-DD-` prefix that Jekyll uses for date and permalink resolution.

For Chirpy-specific writing syntax and optional post features, consult `.claude/skills/write-post/SKILL.md` when available. It covers preview images, prompts, image alignment/dark-light/shadow, MathJax, Mermaid, code-block filename and line-number options, footnotes, media embeds, TOC/comments/pin flags, and `media_subpath`.
