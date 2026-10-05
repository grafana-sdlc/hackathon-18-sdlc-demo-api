#!/usr/bin/env bash
set -euo pipefail
phase=${1:?Use 01-deploy-initial.sh or 02-deploy-updated.sh}
shift
[[ "$phase" == initial || "$phase" == updated ]] || exit 2
repo=grafana-sdlc/sdlc-demo-api
context=${KUBE_CONTEXT:-dev-us-east-0}
namespace=${DEMO_NAMESPACE:-sdlc-o11y}
root=$(cd "$(dirname "$0")/.." && pwd)
for tool in gh kubectl python3; do command -v "$tool" >/dev/null || { echo "Missing: $tool" >&2; exit 1; }; done
if [[ $# -gt 1 ]]; then echo 'Usage: script [full-commit-SHA]' >&2; exit 2; fi
sha=${1:-$(gh api "repos/$repo/commits/main" --jq .sha)}
[[ "$sha" =~ ^[0-9a-f]{40}$ ]] || { echo 'Expected a full commit SHA.' >&2; exit 2; }
run=$(gh run list --repo "$repo" --workflow build.yml --branch main --commit "$sha" --limit 30 --json databaseId,event --jq '[.[] | select(.event == "push" or .event == "workflow_dispatch")][0].databaseId // empty')
[[ -n "$run" ]] || { echo "No main build found for $sha. Wait for GitHub to start it and retry." >&2; exit 1; }
echo "Waiting for https://github.com/$repo/actions/runs/$run"
gh run watch "$run" --repo "$repo" --exit-status
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
gh run download "$run" --repo "$repo" --name deployment-image --dir "$scratch"
image=$(python3 - "$scratch/image.json" "$sha" "$run" <<'PY'
import json, re, sys
record = json.load(open(sys.argv[1]))
assert record['image'] == 'ghcr.io/grafana-sdlc/sdlc-demo-api', 'Unexpected image'
assert record['sha'] == sys.argv[2] and record['run'] == sys.argv[3], 'Build metadata mismatch'
assert re.fullmatch(r'sha256:[0-9a-f]{64}', record['digest']), 'Invalid digest'
print(record['image'] + '@' + record['digest'])
PY
)
k=(kubectl --context "$context" --namespace "$namespace" --request-timeout=30s)
"${k[@]}" get namespace "$namespace" -o name >/dev/null
existing=$("${k[@]}" get deployment sdlc-demo-api --ignore-not-found -o jsonpath='{.spec.template.spec.containers[0].image}')
if [[ "$phase" == initial && -n "$existing" && "$existing" != "$image" ]]; then
 echo 'A different image is already deployed; use Script 2.' >&2; exit 1
fi
if [[ "$phase" == updated && ( -z "$existing" || "$existing" == "$image" ) ]]; then
 echo 'Script 2 requires an existing deployment and a different image. Merge the suggested PR and wait for its build.' >&2; exit 1
fi
python3 "$root/scripts/render.py" "$namespace" "$image" "$sha" > "$scratch/resources.json"
echo "Deploying $image to $context / $namespace"
if [[ "$phase" == updated ]]; then
 # Only change the image and source revision; preserve resource-demo settings.
 python3 - "$scratch/resources.json" > "$scratch/image-patch.json" <<'PATCH'
import json, sys
items = json.load(open(sys.argv[1]))['items']
template = next(x for x in items if x['kind'] == 'Deployment')['spec']['template']
container = template['spec']['containers'][0]
print(json.dumps({'spec': {'template': {
    'metadata': {'annotations': template['metadata']['annotations']},
    'spec': {'containers': [{'name': container['name'], 'image': container['image']}]}
}}}))
PATCH
 "${k[@]}" patch deployment/sdlc-demo-api --type=strategic --patch-file "$scratch/image-patch.json" --dry-run=server >/dev/null
 "${k[@]}" patch deployment/sdlc-demo-api --type=strategic --patch-file "$scratch/image-patch.json"
else
 "${k[@]}" apply --dry-run=server -f "$scratch/resources.json" >/dev/null
 "${k[@]}" apply -f "$scratch/resources.json"
fi
"${k[@]}" rollout status deployment/sdlc-demo-api --timeout=180s
"${k[@]}" get pods -l app.kubernetes.io/name=sdlc-demo-api -o wide
echo "Filter the SDLC App by deployment name: sdlc-demo-api"
echo "Build: https://github.com/$repo/actions/runs/$run"
echo "Test: kubectl --context $context -n $namespace port-forward service/sdlc-demo-api 8080:8080"
