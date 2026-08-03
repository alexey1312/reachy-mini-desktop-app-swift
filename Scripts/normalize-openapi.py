#!/usr/bin/env python3
"""Normalize the daemon OpenAPI spec for swift-openapi-generator.

FastAPI/Pydantic v2 encodes nullable fields as `anyOf: [X, {"type": "null"}]`.
swift-openapi-generator does not support `type: null` branches (upstream issues
apple/swift-openapi-generator#906, #817) and silently drops such properties,
producing empty structs.

Stripping the null branch alone is not enough: Pydantic marks `Optional[X]`
without a default as *required and nullable* (e.g. `DaemonStatus.backend_status`,
which a stopped daemon sends as null). Such a property must also leave `required`,
or the generated Swift field is non-Optional and decoding a real null throws.

Usage: normalize-openapi.py <spec.json>   (rewrites the file in place)
"""
import json
import sys


def is_nullable(schema):
    return isinstance(schema, dict) and any(
        branch == {"type": "null"} for branch in schema.get("anyOf", [])
    )


def relax_nullable_required(node):
    """Drop required+nullable properties from `required`, before the null branch is gone."""
    if isinstance(node, list):
        for item in node:
            relax_nullable_required(item)
        return
    if not isinstance(node, dict):
        return

    properties = node.get("properties")
    required = node.get("required")
    if isinstance(properties, dict) and isinstance(required, list):
        remaining = [name for name in required if not is_nullable(properties.get(name))]
        if remaining:
            node["required"] = remaining
        else:
            node.pop("required")

    for value in node.values():
        relax_nullable_required(value)


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
    relax_nullable_required(spec)
    strip_null_branches(spec)
    with open(path, "w") as f:
        json.dump(spec, f, indent=1, ensure_ascii=False)
        f.write("\n")
    print(f"normalized {path}")


if __name__ == "__main__":
    main()
