# Hugo Book Theme Test

[![Hugo](https://img.shields.io/badge/hugo-0.79-blue.svg)](https://gohugo.io)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Build with Hugo](https://github.com/alex-shpak/hugo-book/workflows/Build%20with%20Hugo/badge.svg)

### [Hugo](https://gohugo.io) documentation theme as simple as plain book

![Screenshot](https://raw.githubusercontent.com/alex-shpak/hugo-book/master/images/screenshot.png)

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Menu](#menu)
- [Blog](#blog)
- [Configuration](#configuration)
- [Shortcodes](#shortcodes)
- [Versioning](#versioning)
- [Contributing](#contributing)

## Features

- Clean simple design
- Light and Mobile-Friendly
- Multi-language support
- Customisable
- Zero initial configuration
- Handy shortcodes
- Comments support
- Simple blog and taxonomy
- Primary features work without JavaScript
- Dark Mode

## Requirements

- Hugo 0.79 or higher
- Hugo extended version, [Installation Instructions](https://gohugo.io/installation/)

## Installation

### Install as git submodule
Navigate to your hugo project root and run:

```
git submodule add https://github.com/alex-shpak/hugo-book themes/hugo-book
```

Then run hugo (or set `theme = "hugo-book"`/`theme: hugo-book` in configuration file)

```
hugo server --minify --theme hugo-book
```

### Install as hugo module

You can also add this theme as a Hugo module instead of a git submodule.

Start with initializing hugo modules, if not done yet:
```
hugo mod init github.com/repo/path
```

Navigate to your hugo project root and add [module] section to your `config.toml`:

```toml
[module]
[[module.imports]]
path = 'github.com/alex-shpak/hugo-book'
```

Then, to load/update the theme module and run hugo:

```sh
hugo mod get -u
hugo server --minify
```

### Creating site from scratch

Below is an example on how to create a new site from scratch:

```sh
hugo new site mydocs; cd mydocs
git init
git submodule add https://github.com/alex-shpak/hugo-book themes/hugo-book
cp -R themes/hugo-book/exampleSite/content.en/* ./content
```

```sh
hugo server --minify --theme hugo-book
```