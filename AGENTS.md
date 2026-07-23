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
- `_interview/`: Password-protected interview articles (the `interview` collection). See "Interview Articles" below. Never put these in `_posts/`.
- `_data/`: Small YAML overrides consumed by the theme, such as `contact.yml` and `share.yml`.
- `_plugins/`: Repository-local Jekyll plugins and hooks.
- `_config.yml`: Site configuration, including Giscus, PWA cache, pagination, permalink structure, and Jekyll exclusions. Do not change the `/posts/:title/` permalink structure without updating existing post links.
- `assets/`: Static assets and self-hosted images/media.
- `CNAME`: Custom GitHub Pages domain.
- `_site/` and `.jekyll-cache/`: Generated output. They are ignored by Git and must not be edited directly.

## Working With Posts

When adding or editing a post, match frontmatter in recent files under `_posts/`; do not invent a new schema. Filenames must preserve the `YYYY-MM-DD-` prefix that Jekyll uses for date and permalink resolution.

Content images are hosted on jsDelivr (`https://cdn.jsdelivr.net/gh/hxmeie/tuchuang/images/...`). Image URLs must end in a standard extension — `.webp`, `.jpg`, or `.png` — and **never `.awebp`**. Some upload tools (PicGo/Typora) emit `.awebp` filenames; jsDelivr serves `.awebp` as `application/octet-stream` instead of `image/webp`, which the theme's GLightbox lightbox fails to recognize as an image, so clicking a `.awebp` image downloads the file instead of opening the preview (the inline `<img>` still displays via content sniffing, so the page looks fine until you click). When you encounter `.awebp`, rename the file to `.webp` in the `hxmeie/tuchuang` image repo (`git mv` + push) and update the post URLs to match.

## Interview Articles (Password-Protected)

Interview articles live in the `interview` collection, **not** in `_posts/`. They appear only under the sidebar **面试** tab, behind a client-side password gate, and are hidden from the home page, archives, categories, tags, RSS feed, sitemap, and site search. This is a *soft* gate: the content still ships in the HTML, so it deters casual browsing but is not real encryption. Do not treat it as confidential.

To make an article show up under the 面试 tab, the only thing that matters is **its folder** — put the `.md` file in `_interview/`. The `categories: [面试]` category is unrelated; a file left in `_posts/` with that category stays public and does **not** enter the 面试 tab.

Rules for `_interview/*.md`:

- **Location**: must be in `_interview/`. Filenames keep the `YYYY-MM-DD-title.md` prefix; the date is stripped for the URL, yielding `/interview/:title/`.
- **Required frontmatter**: `title` and `date` (the tab list sorts by `date` descending, and the post layout renders it). Obtain `date` from `date "+%Y-%m-%d %H:%M:%S %z"`.
- **Do not set `layout`**: the `interview` layout is applied automatically via `_config.yml` defaults. It wraps the body in `.interview-protected` (hidden until unlock) and includes the gate.
- **Defaults already set** for the collection: `comments: false`, `toc: false` (TOC would leak headings of a locked article), `sitemap: false`. Override per-file only with a clear reason.
- **`categories`/`tags` are optional and cosmetic here** — they render on the article page but generate no category/tag pages (collection items are not in `site.categories`/`site.tags`), so those links go nowhere.
- `image`, `mermaid: true`, `math: true`, etc. work as in normal posts.

Password: the SHA-256 hash lives in `_includes/interview-gate.html` as `PW_HASH`. Change it with `printf '%s' '新口令' | shasum -a 256`. The mechanism uses `sessionStorage` so one unlock covers the whole browsing session; its script is deferred to DOM-ready so revisiting the tab keeps the content revealed.

## Chirpy Writing Syntax

For Chirpy-specific writing syntax and optional post features, consult `.claude/skills/write-post/SKILL.md` when available. It covers preview images, prompts, image alignment/dark-light/shadow, MathJax, Mermaid, code-block filename and line-number options, footnotes, media embeds, TOC/comments/pin flags, and `media_subpath`.
