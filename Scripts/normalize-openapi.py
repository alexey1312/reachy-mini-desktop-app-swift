#!/usr/bin/env python3
"""Normalize the daemon OpenAPI spec for swift-openapi-generator.

FastAPI/Pydantic v2 encodes nullable fields as `anyOf: [X, {"type": "null"}]`.
swift-openapi-generator does not support `type: null` branches (upstream issues
apple/swift-openapi-generator#906, #817) and silently drops such properties,
producing empty structs. Optionality is preserved anyway: these properties are
not in `required`, so the generated Swift fields are Optional, and explicit
JSON nulls decode as nil via decodeIfPresent.

Usage: normalize-openapi.py <spec.json>   (rewrites the file in place)
"""
import json
import sys


def strip_null_branches(node):
    if isinstance(node, list):
        for item in node:
            strip_null_branches(item)
        return
    if not isinstance(node, dict):
        return

    any_of = node.get("anyOf")
    if isinstance(any_of, list):
        remaining = [b for b in any_of if b != {"type": "null"}]
        if len(remaining) == 1:
            branch = remaining[0]
            node.pop("anyOf")
            if "$ref" in branch:
                # Bare $ref; siblings like `title` are dropped (ignored by 3.1 tools anyway)
                node.clear()
            node.update(branch)
        elif remaining:
            node["anyOf"] = remaining

    for value in node.values():
        strip_null_branches(value)


def main():
    path = sys.argv[1]
    with open(path) as f:
        spec = json.load(f)
    strip_null_branches(spec)
    with open(path, "w") as f:
        json.dump(spec, f, indent=1, ensure_ascii=False)
        f.write("\n")
    print(f"normalized {path}")


if __name__ == "__main__":
    main()
