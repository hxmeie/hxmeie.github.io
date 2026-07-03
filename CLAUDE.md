# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A personal Jekyll blog (哆啦A梦小短腿 / hxmeie) built on the [jekyll-theme-chirpy](https://github.com/cotes2020/jekyll-theme-chirpy) gem (v7.2.4, pulled in as a dependency via `Gemfile`, not forked into the repo). Deployed to GitHub Pages via GitHub Actions on every push to `master`. Content is almost entirely Chinese-language Android/Kotlin technical notes and interview prep.

Because the theme is consumed as a gem rather than forked, this repo only contains site-specific content and overrides — there is no theme source code, no `assets/js` build pipeline, and no `package.json` to maintain here.

## Commands

```bash
bundle install                              # install Ruby deps (first-time setup)
bundle exec jekyll serve                    # local dev server with live rebuild, http://localhost:4000
bundle exec jekyll build                    # production build → ./_site
JEKYLL_ENV=production bundle exec jekyll build --baseurl ""   # mirror the CI build exactly (see .github/workflows/jekyll.yml)
```

There is no test suite, linter, or single-file test runner in this repo — `html-proofer` is present in the `Gemfile` (`:test` group) but is not currently wired into a script, so there's nothing to "run one test" against. Validate changes by building the site and/or running `jekyll serve` and checking the page in a browser.

Deployment is automatic: pushing to `master` triggers `.github/workflows/jekyll.yml`, which builds with Jekyll and deploys `_site` to GitHub Pages. There is no manual deploy step.

## Structure and conventions

- `_posts/` — blog posts, standard Jekyll `YYYY-MM-DD-title.md` naming. Frontmatter convention used throughout:
  ```yaml
  categories: [分类1, 分类2]
  title: 标题
  date: 2023-05-19 13:28:00 +0800
  tags: [标签1, 标签2]
  keywords: [关键词1, 关键词2]
  image:
    path: <cover image URL>
    lqip: /assets/img/placeholder.webp
  ```
  Do **not** hand-add `last_modified_at` — `_plugins/posts-lastmod-hook.rb` derives it automatically from each post file's git commit history at build time (posts with more than one commit get a `last_modified_at` from `git log`). This means a post's "updated" date only changes once the file is actually committed again.
- `_tabs/` — top-level nav pages (About, Archives, Categories, Tags), rendered via the `tabs` collection configured in `_config.yml`.
- `_data/` — small YAML overrides consumed by the theme (e.g. `contact.yml`, `share.yml`).
- `_plugins/` — repo-local Jekyll plugins/hooks; currently just the lastmod git hook above.
- `_config.yml` — all site configuration lives here: comments (giscus, repo `hxmeie/hxmeie.github.io`), PWA/offline cache, pagination, permalink structure (`/posts/:title/` — the config explicitly warns not to change this without updating all existing post links), and the `exclude:` list of files Jekyll should not process into the site.
- `assets/` — static assets and any self-hosted images/media referenced by posts (most post images are hotlinked to an external CDN via jsDelivr/GitHub, per the `image.path` frontmatter pattern above).
- `CNAME` — custom domain for GitHub Pages.
- `_site/` and `.jekyll-cache/` — build output, gitignored, never edit directly.

## Working with posts

When adding or editing a post, match the existing frontmatter shape (categories/title/date/tags/keywords/image) seen in recent `_posts/` entries rather than inventing a new schema. Filenames must keep the `YYYY-MM-DD-` date prefix Jekyll expects for permalink/date resolution.
