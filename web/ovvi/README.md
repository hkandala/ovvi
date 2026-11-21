# @ovvi/plugin-api

TypeScript types for the `ovvi` object that an [Ovvi](https://ovvi.dev) plugin's page gets (plugin API version 3).
Types only: Ovvi gives the object to the page at run time, so a plugin never bundles this package.

## Use it

```sh
npm install --save-dev @ovvi/plugin-api
```

```ts
import type { Ovvi } from "@ovvi/plugin-api"
```

To start a plugin, see [Create a plugin](https://ovvi.dev/docs/plugins/create). The full reference is
[The plugin API](https://ovvi.dev/docs/plugins/api).

MIT license.
