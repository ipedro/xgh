#!/usr/bin/env bash
# ct-manifest.sh — Manifest (_manifest.json) and index (_index.md) management
# Sourced by context-tree.sh; can also be sourced directly.

rebuild_manifest() {
  local ct_dir="$1"
  local manifest="${ct_dir}/_manifest.json"

  local team version created
  team=$(python3 -c "import json; m=json.load(open('${manifest}')); print(m.get('team','unknown'))" 2>/dev/null || echo "unknown")
  version=$(python3 -c "import json; m=json.load(open('${manifest}')); print(m.get('version',1))" 2>/dev/null || echo "1")
  created=$(python3 -c "import json; m=json.load(open('${manifest}')); print(m.get('created',''))" 2>/dev/null || echo "")

  python3 << PYEOF
import json, os, re, sys
from pathlib import Path
import datetime

ct_dir = Path('${ct_dir}')
domains = {}

for md_file in sorted(ct_dir.rglob('*.md')):
    name = md_file.name
    if name.startswith('_') or name == 'context.md' or name.endswith('.stub.md'):
        continue

    rel = md_file.relative_to(ct_dir)
    parts = rel.parts
    if len(parts) < 2:
        continue

    domain_name = parts[0]
    if domain_name == '_archived':
        continue

    fields = {}
    try:
        with open(md_file, 'r') as f:
            lines = f.readlines()
        if lines and lines[0].strip() == '---':
            in_fm = False
            count = 0
            for line in lines:
                if line.strip() == '---':
                    count += 1
                    if count == 1:
                        in_fm = True
                        continue
                    else:
                        break
                if in_fm:
                    m = re.match(r'^(\w+):\s*(.*)', line.strip())
                    if m:
                        fields[m.group(1)] = m.group(2)
    except:
        pass

    if domain_name not in domains:
        domains[domain_name] = {'name': domain_name, 'entries': []}

    entry = {
        'path': str(rel),
        'title': fields.get('title', name.replace('.md', '')),
        'maturity': fields.get('maturity', 'draft'),
        'importance': int(fields.get('importance', '0')),
        'tags': fields.get('tags', '[]'),
        'updatedAt': fields.get('updatedAt', ''),
    }
    domains[domain_name]['entries'].append(entry)

manifest = {
    'version': ${version},
    'team': '${team}',
    'created': '${created}',
    'lastRebuilt': datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'),
    'domains': list(domains.values()),
}

with open('${manifest}', 'w') as f:
    json.dump(manifest, f, indent=2)
PYEOF
}

add_to_manifest() {
  local ct_dir="$1" rel_path="$2" title="$3" maturity="$4" importance="$5"
  local manifest="${ct_dir}/_manifest.json"

  python3 << PYEOF
import json, sys
from pathlib import Path

manifest_path = '${manifest}'
rel_path = '${rel_path}'
title = '${title}'
maturity = '${maturity}'
importance = int('${importance}')

with open(manifest_path, 'r') as f:
    m = json.load(f)

parts = Path(rel_path).parts
domain_name = parts[0] if parts else 'unknown'

domain = None
for d in m.get('domains', []):
    if d['name'] == domain_name:
        domain = d
        break

if domain is None:
    domain = {'name': domain_name, 'entries': []}
    m.setdefault('domains', []).append(domain)

existing = [e for e in domain['entries'] if e['path'] == rel_path]
if not existing:
    domain['entries'].append({
        'path': rel_path,
        'title': title,
        'maturity': maturity,
        'importance': importance,
    })

with open(manifest_path, 'w') as f:
    json.dump(m, f, indent=2)
PYEOF
}

remove_from_manifest() {
  local ct_dir="$1" rel_path="$2"
  local manifest="${ct_dir}/_manifest.json"

  python3 << PYEOF
import json

manifest_path = '${manifest}'
rel_path = '${rel_path}'

with open(manifest_path, 'r') as f:
    m = json.load(f)

for domain in m.get('domains', []):
    domain['entries'] = [e for e in domain.get('entries', []) if e['path'] != rel_path]

m['domains'] = [d for d in m.get('domains', []) if d.get('entries')]

with open(manifest_path, 'w') as f:
    json.dump(m, f, indent=2)
PYEOF
}

generate_index() {
  local ct_dir="$1"

  for domain_dir in "${ct_dir}"/*/; do
    [ -d "$domain_dir" ] || continue
    local domain_name
    domain_name=$(basename "$domain_dir")
    [[ "$domain_name" == _* ]] && continue

    local index_file="${domain_dir}/_index.md"

    python3 << PYEOF
import os, re
from pathlib import Path

domain_dir = Path('${domain_dir}')
domain_name = '${domain_name}'
entries = []

for md_file in sorted(domain_dir.rglob('*.md')):
    name = md_file.name
    if name.startswith('_') or name == 'context.md' or name.endswith('.stub.md'):
        continue

    fields = {}
    body_lines = []
    try:
        with open(md_file, 'r') as f:
            lines = f.readlines()
        if lines and lines[0].strip() == '---':
            count = 0
            past_fm = False
            for line in lines:
                if line.strip() == '---':
                    count += 1
                    if count == 2:
                        past_fm = True
                    continue
                if not past_fm and count == 1:
                    m = re.match(r'^(\w+):\s*(.*)', line.strip())
                    if m:
                        fields[m.group(1)] = m.group(2)
                elif past_fm:
                    body_lines.append(line)
    except:
        pass

    rel = md_file.relative_to(domain_dir)
    title = fields.get('title', name.replace('.md', ''))
    maturity = fields.get('maturity', 'draft')
    importance = fields.get('importance', '0')
    tags = fields.get('tags', '[]')

    body = ''.join(body_lines).strip()
    summary = body[:150].replace('\n', ' ').strip()
    if len(body) > 150:
        summary += '...'

    entries.append({
        'path': str(rel),
        'title': title,
        'maturity': maturity,
        'importance': importance,
        'tags': tags,
        'summary': summary,
    })

entries.sort(key=lambda e: int(e.get('importance', '0')), reverse=True)

with open('${index_file}', 'w') as f:
    f.write(f'# {domain_name}\n\n')
    f.write(f'> Auto-generated index. {len(entries)} entries.\n\n')
    for e in entries:
        f.write(f'### {e["title"]}\n')
        f.write(f'- **Path:** {e["path"]}\n')
        f.write(f'- **Maturity:** {e["maturity"]} | **Importance:** {e["importance"]}\n')
        f.write(f'- **Tags:** {e["tags"]}\n')
        if e['summary']:
            f.write(f'- {e["summary"]}\n')
        f.write('\n')
PYEOF
  done
}
