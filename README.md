# SDLC demo API

A tiny Go API for demonstrating deployment observation, suggested CI instrumentation,
image provenance, and pipeline navigation in the Grafana SDLC App.

- `GET /healthz` returns health status.
- `GET /api/hello` returns a greeting, service name, and the baked-in Git commit SHA.
- No database, external API, or runtime secrets are needed.

## Build and publish

Every push to `main` (including a merged pull request) tests, builds, and publishes
`ghcr.io/grafana-sdlc/sdlc-demo-api:sha-<full-commit-SHA>`.
Pull requests targeting `main` test and build without publishing. You can also run
the workflow manually on `main`. Images target Linux AMD64; the Deployment selects
AMD64 nodes. The workflow uploads an `image.json` artifact containing the exact
manifest digest, commit, and workflow run ID. Deployment scripts use this digest,
never a mutable tag.

The initial workflow deliberately omits the SDLC reporting action. Use the App's
suggested PR to add it during the demo. Docker's own build provenance is disabled;
the reporting action added by the PR creates/uploads the signed provenance.

**One-time setup:** install/connect the SDLC GitHub App for this repository and
associate it with the Grafana stack observing your cluster. Enable its pipeline
subscriptions if pipeline navigation is part of your demo. After the first build,
set the GHCR container package visibility to **Public** in its package settings;
GitHub initially creates container packages as private, even for public repos.
This avoids cluster image-pull credentials. See [GitHub's container registry guide](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry).

## Demo

Prerequisites: Bash, `gh` authenticated with repository/Actions read access,
`kubectl` with cluster access, and Python 3. Your cluster must already be observed
by the SDLC receiver. Defaults are context `dev-us-east-0` and dedicated namespace
`sdlc-demo-api`; override with `KUBE_CONTEXT` and `DEMO_NAMESPACE`.

### 1. Deploy the initial image

```sh
./scripts/01-deploy-initial.sh
```

This selects the current `main` commit's build, waits for it, downloads its digest,
and creates one small Deployment and a ClusterIP Service. It annotates the resources
with `kustomize.toolkit.fluxcd.io/reconcile: disabled`, allowing manual demo updates.
The annotation disables Flux reconciliation; it does not itself enable SDLC observation.
No public ingress is created.

In the SDLC App, filter by deployment name **sdlc-demo-api**. Wait for the first
successful rollout and missing provenance to appear.

### 2. Merge the App's suggested PR

In the App, scan this repository and create/review its suggested instrumentation PR.
Merge it, then wait for the `Build and publish API` workflow to succeed. The action
must report to the same SDLC stack that observes the deployment. Ensure the added
step only reports published images (main pushes, not PR validation builds).

### 3. Deploy the instrumented build

```sh
./scripts/02-deploy-updated.sh
```

Script 2 selects the new `main` build and refuses to proceed if its image digest
matches the deployed image. Each image includes the commit SHA, so a workflow-only
PR also creates a distinct image and rollout. In the App, watch the second rollout,
its linked repository/commit, and signed image provenance. Navigate to its pipeline
when that UI and the pipeline subscription are enabled.

Both scripts accept a full commit SHA as their optional first argument for repeatable
runs. Workflow artifacts expire after 90 days; rerun the workflow if needed.
Script 1 refuses to overwrite a different existing image. Script 2 requires the
initial Deployment to exist. Neither script merges PRs or changes app installation.

### Test the live API

```sh
kubectl --context dev-us-east-0 -n sdlc-demo-api port-forward service/sdlc-demo-api 8080:8080
# In another terminal:
curl http://localhost:8080/api/hello
```

### Local development

```sh
go test ./...
go run .
# Or:
docker build --build-arg REVISION=local -t sdlc-demo-api .
docker run --rm -p 8080:8080 sdlc-demo-api
```

### Cleanup

Delete only this demo's dedicated namespace after the demo:

```sh
kubectl --context dev-us-east-0 delete namespace sdlc-demo-api
```

Use your overridden context/namespace if applicable. Deleting the namespace deletes
all resources inside it. To show a clean first-run provenance gap again, use a new
uninstrumented commit: previously reported digest provenance can remain in SDLC.
