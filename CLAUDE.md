# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Hugo-based personal website (77hdumat.github.io) using the hugo-book theme. The site is configured in Korean (`ko-kr`) and uses GitHub Pages for hosting with a two-repository deployment strategy.

## Build and Deployment

### Build the Site
```bash
hugo -t hugo-book
```

### Deploy to GitHub Pages
```bash
./deploy.sh
```

The deployment script:
1. Builds the site with `hugo -t hugo-book`
2. Commits and pushes the generated files in `public/` to the `github-pages` branch (submodule)
3. Commits and pushes source files to the `main` branch

You can pass a custom commit message:
```bash
./deploy.sh "Your custom commit message"
```

### Local Development
```bash
hugo server -t hugo-book
```

## Architecture

### Repository Structure
- `content/` - Markdown content files
  - `_index.md` - Homepage (resume)
  - `docs/Server/` - Documentation pages (migrated from `shortcodes/`)
  - `posts/` - Blog posts
  - `menu/` - Menu items
- `layouts/partials/docs/` - Custom Hugo template overrides
  - `comments.html` - Utterances comment system integration
  - `inject/head.html` - Custom head injections (Google Fonts preconnect)
  - `inject/menu-after.html` - GitHub link in sidebar footer
- `assets/_custom.scss` - Custom styles (Noto Sans KR font, heading styles, accent colors)
- `themes/hugo-book/` - Git submodule (forked theme from 77hdumat/hugo-book)
- `public/` - Git submodule pointing to `github-pages` branch (generated site, **DO NOT MODIFY**)

### Git Submodules
The repository uses two submodules:
1. `public/` → `github-pages` branch (deployment target)
2. `themes/hugo-book/` → custom fork at 77hdumat/hugo-book

### Theme Customization
The site uses hugo-book theme with customizations through:
- Custom SCSS in `assets/_custom.scss` (Noto Sans KR font, custom colors: `--accent-color: #614CF6`, `--accent-orange: #F6A54C`)
- Layout overrides in `layouts/partials/docs/`
- Comments enabled via `params.BookComments: true` in `hugo.yaml`
- Utterances integration for GitHub-based comments (repo: 77hdumat/77hdumat.github.io)

### Important Configuration
- **Base URL**: https://77hdumat.github.io/
- **Theme**: hugo-book (submodule)
- **Language**: Korean (ko-kr)
- **Markdown Handler**: goldmark
- **Hugo Version**: v0.152.2+extended (as of last check)

## Critical Rules

1. **Never modify the `public/` directory** - It's a git submodule managed by the deployment script
2. When editing content, work in the `content/` directory
3. Custom styles go in `assets/_custom.scss`
4. Template overrides go in `layouts/partials/docs/`
5. The deployment script handles both source and built site commits automatically