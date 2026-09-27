# Keep Stuff GitHub App

Watches installed repositories for a .addkeep file containing the import: import treatwashere/keep-stuff@main

When that import is found, the service creates .github/workflows/keep-stuff.yml if it does not already exist.

## GitHub App permissions

The registered App needs repository Contents: Read & write and Workflows: Read & write, plus the Push webhook event.

The App needs a public HTTPS webhook endpoint so GitHub can deliver events. Never commit the App private key or webhook secret.

## Run

Requires Node.js 20+.

1. Copy .env.example to .env and fill in the App credentials.
2. Run npm install.
3. Run npm start.
4. Set the GitHub App webhook URL to https://YOUR-HOST/webhooks/github.
