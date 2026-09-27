import express from "express";
import crypto from "node:crypto";
import { App } from "@octokit/app";

const server = express();
const port = Number(process.env.PORT || 3000);

const githubApp = new App({
  appId: process.env.GITHUB_APP_ID,
  privateKey: process.env.GITHUB_PRIVATE_KEY?.replace(/\\n/g, "\n"),
  webhooks: { secret: process.env.GITHUB_WEBHOOK_SECRET }
});

const WORKFLOW_PATH = ".github/workflows/keep-stuff.yml";
const EXPECTED_IMPORT = "treatwashere/keep-stuff@main";

server.get("/", (_req, res) => res.status(200).send("Keep Stuff GitHub App is running."));

async function ensureWorkflow(owner, repo, installationId) {
  const octokit = await githubApp.getInstallationOctokit(installationId);

  let marker;
  try {
    const response = await octokit.rest.repos.getContent({ owner, repo, path: ".addkeep" });
    if (Array.isArray(response.data) || !response.data.content) return;
    marker = Buffer.from(response.data.content, response.data.encoding).toString("utf8");
  } catch (error) {
    if (error.status === 404) return;
    throw error;
  }

  const valid = marker.split(/\\r?\\n/).some(line => line.trim() === `import ${EXPECTED_IMPORT}`);
  if (!valid) return;

  try {
    await octokit.rest.repos.getContent({ owner, repo, path: WORKFLOW_PATH });
    return;
  } catch (error) {
    if (error.status !== 404) throw error;
  }

  const workflow = `name: Keep Stuff

on:
  push:
  create:
  delete:
  workflow_dispatch:

permissions:
  contents: write

jobs:
  keep:
    if: github.ref != 'refs/heads/keep-stuff-state'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - uses: ${EXPECTED_IMPORT}
`;

  await octokit.rest.repos.createOrUpdateFileContents({
    owner,
    repo,
    path: WORKFLOW_PATH,
    message: "Add Keep Stuff workflow",
    content: Buffer.from(workflow, "utf8").toString("base64")
  });
}

githubApp.webhooks.on("push", async ({ payload }) => {
  const installationId = payload.installation?.id;
  const owner = payload.repository?.owner?.login;
  const repo = payload.repository?.name;
  if (installationId && owner && repo) await ensureWorkflow(owner, repo, installationId);
});

githubApp.webhooks.onError(async error => console.error("Webhook error:", error));

server.use(express.raw({ type: "application/json" }));

server.post("/webhooks/github", async (req, res) => {
  const event = req.header("x-github-event");
  const delivery = req.header("x-github-delivery");
  const signature = req.header("x-hub-signature-256");

  if (!signature || !process.env.GITHUB_WEBHOOK_SECRET) return res.status(401).send("Missing webhook signature.");

  const expected = "sha256=" + crypto
    .createHmac("sha256", process.env.GITHUB_WEBHOOK_SECRET)
    .update(req.body)
    .digest("hex");

  const a = Buffer.from(signature);
  const b = Buffer.from(expected);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return res.status(401).send("Invalid signature.");

  try {
    await githubApp.webhooks.verifyAndReceive({
      id: delivery,
      name: event,
      signature,
      payload: req.body.toString("utf8")
    });
    res.status(202).send("Accepted.");
  } catch (error) {
    console.error(error);
    res.status(500).send("Webhook handling failed.");
  }
});

server.listen(port, () => console.log(`Keep Stuff GitHub App listening on port ${port}`));
