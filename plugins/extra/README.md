# Extra plugins

Plugins that this repository keeps and checks (`make lint`) but the app does not carry: install one from its folder
with `npm ci && npm run build` in it, then `ovvi plugins install ~/code/ovvi/plugins/extra/<name>`. The app's
own plugins (File Explorer, Git and the template) are in `plugins/builtin/`.
