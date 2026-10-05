#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
context=${KUBE_CONTEXT:-dev-us-east-0}
namespace=${DEMO_NAMESPACE:-sdlc-o11y}
k=(kubectl --context "$context" --namespace "$namespace" --request-timeout=30s)
command=${1:-help}
if (($#)); then shift; fi
case "$command" in
 help|-h|--help)
  cat <<'HELP'
Usage: scripts/demo.sh COMMAND
  status                  Show deployment image, resources, readiness and annotations
  initial [commit-SHA]    Deploy a successful main build with baseline CPU/memory
  cpu                     Change CPU request/limit to 40m/200m, preserving memory
  memory                  Change memory request/limit to 32Mi/128Mi, preserving CPU
  resources               Change both CPU and memory to those demonstration values
  reset-resources         Restore baseline 10m/100m CPU and 16Mi/64Mi memory
  image [commit-SHA]      Deploy a different main build; preserve current CPU/memory
  undo                    Roll back one retained Kubernetes revision
  keep                    Disable Flux reconciliation on the demo Deployment and Service
  remove-annotations      Remove the three temporary Flux keys from demo resources
  cleanup                 Delete only the labeled demo Deployment and Service

Defaults: KUBE_CONTEXT=dev-us-east-0, DEMO_NAMESPACE=sdlc-o11y.
Initial/image fetch the immutable digest from a successful main-build artifact.
Merge the provenance PR yourself, then run image with its full merge SHA.
The target namespace must already exist and is never modified.
The demo is manually managed: removing annotations does NOT delete its resources.
Cleanup leaves the namespace and database event/provenance history intact.
For a fresh rollout: cleanup, then initial with an appropriate baseline commit.
Already ingested image provenance persists even if the wizard is reset.
No ingress is created. Use kubectl port-forward service/sdlc-demo-api 8080:8080.
HELP
  exit 0 ;;
 initial) exec "$root/scripts/01-deploy-initial.sh" "$@" ;;
 image) exec "$root/scripts/02-deploy-updated.sh" "$@" ;;
 status|cpu|memory|resources|reset-resources|undo|keep|remove-annotations|cleanup) ;;
 *) echo "Unknown command: $command. Run $0 help." >&2; exit 2 ;;
esac
(($# == 0)) || { echo 'Unexpected arguments.' >&2; exit 2; }
for tool in kubectl python3; do command -v "$tool" >/dev/null; done
resources=(deployment/sdlc-demo-api service/sdlc-demo-api)
# Check only the demo Deployment and Service; never mutate the shared namespace.
for resource in "${resources[@]}"; do
 object=$("${k[@]}" get "$resource" --ignore-not-found -o json)
 [[ -n "$object" ]] || continue
 python3 -c 'import json,sys; x=json.load(sys.stdin); labels=x["metadata"].get("labels",{}); assert labels.get("app.kubernetes.io/name")=="sdlc-demo-api" and labels.get("app.kubernetes.io/part-of")=="sdlc-demo", "Refusing to modify a resource without demo labels"' <<< "$object"
done
case "$command" in
 cpu|memory|resources|reset-resources)
  patch=$(python3 - "$command" <<'PY'
import json, sys
mode = sys.argv[1]
r = {'requests': {}, 'limits': {}}
if mode in ('cpu', 'resources', 'reset-resources'):
 r['requests']['cpu'], r['limits']['cpu'] = ('10m', '100m') if mode == 'reset-resources' else ('40m', '200m')
if mode in ('memory', 'resources', 'reset-resources'):
 r['requests']['memory'], r['limits']['memory'] = ('16Mi', '64Mi') if mode == 'reset-resources' else ('32Mi', '128Mi')
print(json.dumps({'spec': {'template': {'spec': {'containers': [{'name': 'api', 'resources': r}]}}}}))
PY
)
  "${k[@]}" patch deployment/sdlc-demo-api --type=strategic -p "$patch" --dry-run=server >/dev/null
  "${k[@]}" patch deployment/sdlc-demo-api --type=strategic -p "$patch"
  "${k[@]}" rollout status deployment/sdlc-demo-api --timeout=180s ;;
 undo)
  "${k[@]}" rollout undo deployment/sdlc-demo-api
  "${k[@]}" rollout status deployment/sdlc-demo-api --timeout=180s ;;
 keep|remove-annotations)
  key=kustomize.toolkit.fluxcd.io/reconcile
  for resource in "${resources[@]}"; do
   if [[ "$command" == keep ]]; then
    "${k[@]}" annotate "$resource" --overwrite "$key=disabled" \
      "$key-disabled-by=Lantero" \
      "$key-disabled-reason=Temporary grafana-sdlc/sdlc-demo-api walkthrough; managed by scripts/demo.sh"
   else
    "${k[@]}" annotate "$resource" "$key-" "$key-disabled-by-" "$key-disabled-reason-"
   fi
  done ;;
 cleanup)
  "${k[@]}" delete "${resources[@]}" --ignore-not-found --wait=true --timeout=180s
  echo 'Demo Deployment and Service removed. Namespace and event history retained.'
  exit 0 ;;
esac
"${k[@]}" get deployment/sdlc-demo-api service/sdlc-demo-api -o wide
"${k[@]}" get deployment/sdlc-demo-api -o json | python3 -c 'import json,sys; x=json.load(sys.stdin); print(json.dumps({"annotations":x["metadata"].get("annotations",{}),"containers":[{k:c.get(k) for k in ("name","image","resources")} for c in x["spec"]["template"]["spec"]["containers"]]},indent=2))'
