// The build of the card's page. The card runs the CLI by its full path, since Ovvi's login PATH may not have it.
import { build } from "esbuild"

await build({
  entryPoints: ["src/main.ts"],
  bundle: true,
  format: "esm",
  minify: true,
  sourcemap: true,
  target: "safari18",
  outdir: "dist",
  logLevel: "warning",
  define: { PLUGIN_DIR: JSON.stringify(process.cwd()) },
})
