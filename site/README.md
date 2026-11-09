# Glance website

The landing page at **https://glance.edwinencomienda.com**, served by
[Cloudflare Workers static assets](https://developers.cloudflare.com/workers/static-assets/).
No build step and no JavaScript: everything in `public/` is uploaded and served as is.

| File | Purpose |
| --- | --- |
| `public/index.html`, `public/styles.css` | The page |
| `public/404.html` | Not-found page |
| `public/_headers` | Security headers (CSP, HSTS, nosniff…) and image caching |
| `public/og.jpg` | 1200×630 social preview image |
| `public/icon.svg`, `favicon.svg`, `apple-touch-icon.png` | Icons, from `Resources/Logo/` |
| `public/robots.txt`, `public/sitemap.xml` | Crawlers |
| `wrangler.jsonc` | Cloudflare config: Worker `glance-site`, custom domain, no workers.dev URL |

## Local preview

```sh
cd site
npm install   # Wrangler (pinned in package-lock.json)
npm run dev   # http://localhost:8787, with the headers from public/_headers
```

## Deploying

Deploys are manual: nothing deploys on push. Redeploy whenever `site/` changes.

| | |
| --- | --- |
| Cloudflare account | Edwin Encomienda (`wrangler whoami` shows it) |
| Worker | `glance-site` |
| Domain | `glance.edwinencomienda.com` (custom domain on the `edwinencomienda.com` zone) |
| Config | `site/wrangler.jsonc` |

```sh
cd site
npm install                 # if node_modules/ is missing
npx wrangler whoami         # must show the Edwin Encomienda account
npx wrangler deploy --dry-run   # optional: check what would upload
npm run deploy              # = wrangler deploy
```

Then check it's live:

```sh
curl -sI https://glance.edwinencomienda.com/ | grep -iE "^HTTP|content-security-policy"
curl -s https://glance.edwinencomienda.com/ | grep -o "<title>.*</title>"
```

Notes:

- **Not logged in?** `npx wrangler login` opens a browser for OAuth, so a person has
  to run it. In CI or a headless agent session, set `CLOUDFLARE_API_TOKEN` (a token
  with *Workers Scripts: Edit* and *Workers Routes: Edit*, plus *Zone: Read* /
  *DNS: Edit* for the custom domain) and `CLOUDFLARE_ACCOUNT_ID` in the environment.
  Never commit tokens or put them in `wrangler.jsonc`.
- **Custom domain:** the `routes` entry with `"custom_domain": true` makes Wrangler
  create the DNS record and TLS certificate on the first deploy. A new hostname can
  take a minute or two to serve; a TLS error right after the first deploy usually
  just means the certificate is still being issued.
- **Rollback:** `npx wrangler deployments list` shows recent versions;
  `npx wrangler rollback` returns to the previous one.
- **Cache:** HTML and CSS are revalidated on every request (no `Cache-Control`
  set), so changes show up immediately. SVG, PNG and JPG are cached for a day, so
  give a changed image a new file name (or wait a day).
- **Download links** point to GitHub's `releases/latest/download/Glance.dmg`, so an
  app release needs no website deploy.

## Editing

- Keep the copy in step with `README.md` and `docs/FEATURES.md`.
- The CSP in `public/_headers` allows only same-origin styles and images and **no
  scripts**. If you add a script, font or analytics snippet, update the CSP too.
- `og.jpg` and `apple-touch-icon.png` were rendered from SVG with `sips`
  (`sips -s format png in.svg --out out.png`, then
  `sips -s format jpeg -s formatOptions 85`). The share image's URL in
  `index.html` must stay absolute.
