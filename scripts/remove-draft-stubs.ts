// Post-render: with `draft-mode: gone`, Quarto still writes an empty
// "<html ...></html>" stub at each draft's URL. Delete those stubs (and the
// folders they leave empty) so drafts have no public URL at all.
const out = Deno.env.get("QUARTO_PROJECT_OUTPUT_DIR") ?? "_site";
const stub = /^<!DOCTYPE html>\s*<html[^>]*><\/html>\s*$/i;

async function walk(dir: string): Promise<void> {
  for await (const e of Deno.readDir(dir)) {
    const p = `${dir}/${e.name}`;
    if (e.isDirectory && e.name !== "site_libs") await walk(p);
    else if (e.isFile && e.name.endsWith(".html")) {
      const info = await Deno.stat(p);
      if (info.size < 512 && stub.test(await Deno.readTextFile(p))) await Deno.remove(p);
    }
  }
  if (dir !== out) {
    let empty = true;
    for await (const _ of Deno.readDir(dir)) { empty = false; break; }
    if (empty) await Deno.remove(dir);
  }
}
await walk(out);
