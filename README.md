Personal site at [jeffreypost.dev](https://jeffreypost.dev), built with [Quarto](https://quarto.org) (version 1.11.9) and published to GitHub Pages by GitHub Actions.

## Layout

- `homelab/`, `apps/`, `health/`: one folder per section; each page lives in its own folder.
- `about/`: About page.
- `_templates/`: listing templates for the homepage rows and section pages.
- `theme/`, `partials/`, `assets/`: styles, `<head>` includes, and scripts.

## Working on it

```bash
quarto preview --profile dev     # drafts visible
quarto render                    # production build into _site/ (drafts removed)
bash scripts/check-site.sh       # render both profiles and run the site checks
bash tests/check_secrets_test.sh # tests for the pre-commit secrets guard
```

Install the pre-commit guard once per clone:

```bash
printf '#!/bin/sh\nexec bash scripts/check-secrets.sh\n' > .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit
```

Never commit `.env` files, keys, tokens, passwords or real internal hostnames. Sanitise any config quoted in a post.
