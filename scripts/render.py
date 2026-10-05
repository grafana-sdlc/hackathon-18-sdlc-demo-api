"""Render the versioned Kubernetes template with an immutable image reference."""
import json
import pathlib
import re
import sys

namespace, image, sha = sys.argv[1:]
if not re.fullmatch(r'[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?', namespace):
    raise SystemExit('Invalid Kubernetes namespace')
resources = json.loads((pathlib.Path(__file__).resolve().parents[1] / 'deploy/resources.json').read_text())
for item in resources['items']:
    if item['kind'] not in ('Deployment', 'Service'):
        raise SystemExit('Only demo Deployments and Services may be rendered')
    item['metadata']['namespace'] = namespace
    if item['kind'] == 'Deployment':
        item['spec']['template']['spec']['containers'][0]['image'] = image
        item['spec']['template']['metadata']['annotations']['demo.sdlc.dev/revision'] = sha
print(json.dumps(resources, indent=2))
