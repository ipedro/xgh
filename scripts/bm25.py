#!/usr/bin/env python3
"""
BM25 search over context tree markdown files.

Usage: python3 bm25.py <context_tree_dir> <query> [max_results]

Outputs JSON array of results:
  [{"path": "relative/path.md", "score": 0.85, "title": "...", "importance": 50, "recency": 0.9, "maturity": "draft"}, ...]
"""

import sys
import os
import re
import math
import json
from pathlib import Path


def parse_frontmatter(filepath):
    """Parse YAML frontmatter from a markdown file. Returns (fields_dict, body_text)."""
    fields = {}
    body_lines = []
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            lines = f.readlines()
    except (IOError, UnicodeDecodeError):
        return fields, ""

    if not lines or lines[0].strip() != '---':
        return fields, ''.join(lines)

    in_frontmatter = False
    fm_count = 0
    for line in lines:
        stripped = line.strip()
        if stripped == '---':
            fm_count += 1
            if fm_count == 1:
                in_frontmatter = True
                continue
            elif fm_count == 2:
                in_frontmatter = False
                continue
        if in_frontmatter:
            match = re.match(r'^(\w+):\s*(.*)', line.strip())
            if match:
                key, val = match.group(1), match.group(2)
                fields[key] = val
        elif fm_count >= 2:
            body_lines.append(line)

    return fields, ''.join(body_lines)


def tokenize(text):
    """Simple whitespace + punctuation tokenizer, lowercased."""
    text = text.lower()
    text = re.sub(r'[^\w\s-]', ' ', text)
    tokens = text.split()
    return [t for t in tokens if len(t) > 1]


def parse_list_field(val):
    """Parse '[a, b, c]' into ['a', 'b', 'c']."""
    if not val:
        return []
    val = val.strip('[]')
    return [x.strip() for x in val.split(',') if x.strip()]


class BM25:
    """BM25 ranking over a corpus of documents."""

    def __init__(self, k1=1.5, b=0.75):
        self.k1 = k1
        self.b = b
        self.docs = []
        self.df = {}
        self.avgdl = 0
        self.N = 0

    def add_document(self, path, tokens, fields):
        self.docs.append({"path": path, "tokens": tokens, "fields": fields})
        for t in set(tokens):
            self.df[t] = self.df.get(t, 0) + 1

    def build(self):
        self.N = len(self.docs)
        if self.N == 0:
            self.avgdl = 1
            return
        total = sum(len(d["tokens"]) for d in self.docs)
        self.avgdl = total / self.N if self.N > 0 else 1

    def score(self, query_tokens):
        """Score all documents against query. Returns list of (index, score)."""
        results = []
        for i, doc in enumerate(self.docs):
            s = 0.0
            dl = len(doc["tokens"])
            tf_map = {}
            for t in doc["tokens"]:
                tf_map[t] = tf_map.get(t, 0) + 1

            for qt in query_tokens:
                if qt not in self.df:
                    continue
                tf = tf_map.get(qt, 0)
                if tf == 0:
                    continue
                idf = math.log((self.N - self.df[qt] + 0.5) / (self.df[qt] + 0.5) + 1)
                numerator = tf * (self.k1 + 1)
                denominator = tf + self.k1 * (1 - self.b + self.b * dl / self.avgdl)
                s += idf * numerator / denominator

            results.append((i, s))
        return results


def search(context_tree_dir, query, max_results=10):
    """Search context tree files using BM25. Returns JSON results."""
    ct_path = Path(context_tree_dir)
    if not ct_path.exists():
        return []

    md_files = []
    for f in ct_path.rglob('*.md'):
        name = f.name
        if name.startswith('_') or name == 'context.md' or name.endswith('.stub.md'):
            continue
        md_files.append(f)

    if not md_files:
        return []

    bm25 = BM25()
    for f in md_files:
        fields, body = parse_frontmatter(str(f))
        text_parts = []
        if 'title' in fields:
            text_parts.extend([fields['title']] * 3)
        for list_field in ['tags', 'keywords']:
            if list_field in fields:
                items = parse_list_field(fields[list_field])
                text_parts.extend(items * 2)
        text_parts.append(body)

        tokens = tokenize(' '.join(text_parts))
        rel_path = str(f.relative_to(ct_path))
        bm25.add_document(rel_path, tokens, fields)

    bm25.build()

    query_tokens = tokenize(query)
    if not query_tokens:
        return []

    scores = bm25.score(query_tokens)

    max_score = max((s for _, s in scores), default=0)
    if max_score > 0:
        scores = [(i, s / max_score) for i, s in scores]

    scores = [(i, s) for i, s in scores if s > 0.01]
    scores.sort(key=lambda x: x[1], reverse=True)
    scores = scores[:max_results]

    results = []
    for idx, bm25_score in scores:
        doc = bm25.docs[idx]
        fields = doc["fields"]

        importance = 0
        try:
            importance = int(fields.get("importance", "0"))
        except ValueError:
            pass

        recency = 0.0
        try:
            recency = float(fields.get("recency", "0"))
        except ValueError:
            pass

        maturity = fields.get("maturity", "draft")

        results.append({
            "path": doc["path"],
            "bm25_score": round(bm25_score, 4),
            "title": fields.get("title", ""),
            "importance": importance,
            "recency": recency,
            "maturity": maturity,
        })

    return results


if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Usage: bm25.py <context_tree_dir> <query> [max_results]", file=sys.stderr)
        sys.exit(1)

    ct_dir = sys.argv[1]
    query = sys.argv[2]
    max_results = int(sys.argv[3]) if len(sys.argv) > 3 else 10

    results = search(ct_dir, query, max_results)
    print(json.dumps(results, indent=2))
