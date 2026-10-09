# herdr-togglesplit

hyprland `togglesplit` for [herdr](https://herdr.dev). flip the split under your pane.

```
stacked  <->  side by side
```

## install

```bash
herdr plugin install reobin/herdr-togglesplit
herdr server reload-config
```

## use

```toml
[[keys.command]]
key = "prefix+t"
type = "plugin_action"
command = "herdr-togglesplit.toggle"
description = "toggle split direction"
```

single pane, zoomed, or messy layouts just toast and stay put.
