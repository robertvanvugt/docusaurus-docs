# Deploy and Configure Docusaurus

This document describes a step-by-step path to: **scaffold a Docusaurus site**, **move your repo’s Markdown into it**, and **publish via GitHub Pages** in line with the current Docusaurus install + deploy docs. ([docusaurus.io][1])

## 0. Prereqs on Windows

### Install Node.js (required)

1. Install **Node.js 18+** (LTS is best).
2. Verify in a fresh terminal:

   ```powershell
   node -v
   npm -v
   ```

Docusaurus requires Node 18+ (v3+). ([docusaurus.io][2])

### Optional but recommended

* **Git** installed (so you can push + GitHub Actions).
* VS Code (or alternate IDE).

## 1. Create (scaffold) a Docusaurus site

Open PowerShell (or VS Code terminal) in the folder where you want the site.

1. Run the official scaffolder:

   ```powershell
   npx create-docusaurus@latest my-docs classic
   ```

   This creates a new folder `my-docs` with a working site. ([docusaurus.io][1])

   When asked "Which language do you want to use?", select `TypeScript`.

2. Start it locally:

   ```powershell
   cd my-docs
   npm install
   npm run start
   ```

3. Open the local URL it prints (usually `http://localhost:3000`).

---

## 2. Put your repo’s Markdown into Docusaurus

Docusaurus expects docs in the `docs/` folder (by default in the classic template).

### Common approach (simple + works well)

1. Copy your existing `.md` / `.mdx` files into:

   ```
   my-docs/docs/
   ```

2. Make sure each doc has a unique **id** or filename, and ideally a title.

   * Docusaurus uses front matter + file structure to build navigation.

### Sidebars (navigation)

* The classic template usually auto-generates a sidebar from your docs folder, but you can explicitly control it in `sidebars.js`.
* If you want docs to reflect your repo’s folder structure, mirror it under `docs/`.

Tip: If you already have a folder like `/docs` in your GitHub repo, you can **reuse it** by copying contents into Docusaurus’ `docs/` folder, or by restructuring so Docusaurus becomes the root and your docs live under `docs/`.

---

## 3. Key configuration you’ll almost certainly edit

Open `docusaurus.config.js` (or `.ts`) in the site root. This is the main site config file. ([docusaurus.io][3])

Edit these fields early:

* `title` / `tagline`
* `url` (your GitHub Pages domain)
* `baseUrl` (depends on whether you use user/org pages or project pages)
* `organizationName` and `projectName` (used for GitHub Pages deploy)

In our case:

In my-docs/docusaurus.config.* set these (project pages style):

* url: https://robertvanvugt.github.io
* baseUrl: /docusaurus-docs/
* organizationName: robertvanvugt
* projectName: docusaurus-docs

These fields are the core of GitHub Pages deployment for Docusaurus.

---

## 4. Decide how you’ll publish on GitHub Pages

There are **two** GitHub Pages shapes:

### A. User/Org pages

Repo name: `USERNAME.github.io`

* `url`: `https://USERNAME.github.io`
* `baseUrl`: `/`

### B. Project pages

Repo name: anything, e.g. `my-docs`

* `url`: `https://USERNAME.github.io`
* `baseUrl`: `/my-docs/`

This distinction matters because Docusaurus uses `url` + `baseUrl` to generate correct links.

---

## 5. Publish with GitHub Actions (recommended)

Docusaurus supports a static build and deployment flows; GitHub Pages commonly uses Actions now.

### 5.1 Create a GitHub repo and push your Docusaurus site


### 5.2 Enable GitHub Pages to deploy from Actions

In GitHub:

* Repo → **Settings** → **Pages**
* **Build and deployment** → Source: **GitHub Actions** (not “deploy from branch”) ([GitHub][5])

### 5.3 Add a GitHub Actions workflow

Create this file:

```
.github/workflows/deploy.yml
```

```yaml
name: Deploy to GitHub Pages

on:
  push:
    branches:
      - main

jobs:
  build:
    name: Build Docusaurus
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: my-docs

    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: npm
          cache-dependency-path: my-docs/package-lock.json

      - name: Install dependencies
        run: npm ci

      - name: Build website
        run: npm run build

      - name: Upload Build Artifact
        uses: actions/upload-pages-artifact@v3
        with:
          path: my-docs/build

  deploy:
    name: Deploy to GitHub Pages
    needs: build

    permissions:
      pages: write
      id-token: write

    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}

    runs-on: ubuntu-latest
    steps:
      - name: Deploy to GitHub Pages
        id: deployment
        uses: actions/deploy-pages@v4

```

> **Tip!** Use the official Docusaurus deployment guidance as your baseline. ([docusaurus.io][4])

---

## 6. Build + verify locally before deploying

Run:

```powershell
npm run build
npm run serve -- --build
```

This verifies the production build output locally (recommended before pushing changes). ([docusaurus.io][4])

---

## 7. Typical “gotchas” when importing Markdown

* **Relative links** between docs might need adjusting once under `docs/`.
* If you use lots of GitHub-flavored Markdown features, check rendering (Docusaurus uses MDX/remark pipeline).
* If you need versioned docs later, Docusaurus supports versioning, but you can skip that for day 1. ([docusaurus.io][6])

---

## If you tell me these 2 things, I’ll tailor the exact config values

* Your GitHub repo name (and whether it will be `USERNAME.github.io` or a normal repo)
* Where your Markdown lives today (root, `/docs`, multiple folders)

Even without that, the steps above will get you from zero → local site → GitHub Pages-ready.

[1]: https://docusaurus.io/docs/installation "Installation"
[2]: https://docusaurus.io/docs/3.1.1/installation "Installation"
[3]: https://docusaurus.io/docs/api/docusaurus-config "docusaurus.config.js"
[4]: https://docusaurus.io/docs/deployment "Deployment"
[5]: https://github.com/LayZeeDK/github-pages-docusaurus "A Docusaurus website deployed to GitHub Pages using ..."
[6]: https://docusaurus.io/docs/versioning "Versioning"
