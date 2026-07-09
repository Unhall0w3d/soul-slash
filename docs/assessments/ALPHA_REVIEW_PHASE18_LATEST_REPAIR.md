
# Alpha Review Phase 18 Latest Repair

This repair fixes `ruby bin/soul improve alpha-review --latest`.

## Issue

`--latest` originally resolved to the newest proposal folder. When proposal generation created several folders with the same timestamp, the newest lexicographic folder could be rank 4, even if only rank 1 had an alpha folder.

That caused review to fail with:

```text
alpha folder not found
```

## Fix

Alpha generation keeps this behavior:

```bash
ruby bin/soul improve alpha --latest
```

It still selects the newest proposal.

Alpha review now uses the latest alpha-ready proposal:

```bash
ruby bin/soul improve alpha-review --latest
```

That means it selects the newest proposal folder that already contains:

```text
alpha/
```

## Boundaries

This is a locator and CLI routing repair only.

It does not:

```text
promote alpha artifacts
modify production skill paths
modify registries
install packages
download models
```
