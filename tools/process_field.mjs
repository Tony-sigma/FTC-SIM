// Slims the field element CAD in cad/field/ into models/field/ for the simulator.
//   cd tools && npm install && npm run field
// Keeps the CAD's orientation (Y up) and moves the origin to the element's pivot when it has one.
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { dedup, flatten, join, weld, simplify, prune, getBounds } from '@gltf-transform/functions';
import { MeshoptSimplifier } from 'meshoptimizer';
import { readdirSync, mkdirSync, writeFileSync, statSync } from 'node:fs';

const SRC = '../cad/field/', OUT = '../models/field/';
const FASTENER = /screw|nut\b|washer|spacer|cable tie|plug|bearing/i;
// Parts whose centre marks the pivot axis of a moving element.
const PIVOT_PART = { red_hive: /Shielded Flanged Bearing/i };

const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
await MeshoptSimplifier.ready;
mkdirSync(OUT, { recursive: true });
const meshNodes = (n, out = []) => { if (n.getMesh()) out.push(n); n.listChildren().forEach((c) => meshNodes(c, out)); return out; };
const named = (n, re, out = []) => { if (re.test(n.getName())) out.push(n); n.listChildren().forEach((c) => named(c, re, out)); return out; };
const measurements = {};

for (const file of readdirSync(SRC).filter((f) => f.endsWith('.glb'))) {
  const name = file.replace(/\.glb$/, '');
  const doc = await io.read(SRC + file);
  const root = doc.getRoot().listScenes()[0].listChildren()[0];
  let origin = [0, 0, 0];
  if (PIVOT_PART[name]) {
    const bs = named(root, PIVOT_PART[name]).map((n) => getBounds(n));
    origin = [0, 1, 2].map((i) => bs.reduce((t, b) => t + (b.min[i] + b.max[i]) / 2, 0) / bs.length);
  }
  const all = getBounds(root);
  for (const n of meshNodes(root)) if (FASTENER.test(n.getName())) n.dispose();
  root.setTranslation(origin.map((v) => -v));
  await doc.transform(prune(), dedup(), flatten(), join(), weld(),
    simplify({ simplifier: MeshoptSimplifier, ratio: 0.05, error: 0.01 }), prune());
  await io.write(`${OUT}${name}.glb`, doc);
  let tris = 0;
  for (const m of doc.getRoot().listMeshes()) for (const p of m.listPrimitives()) tris += p.getIndices().getCount() / 3;
  const r = (v) => +(v / 0.0254).toFixed(2);
  measurements[name] = { pivot_in_cad_in: origin.map(r), size_in: all.max.map((v, i) => r(v - all.min[i])),
    bounds_from_pivot_in: { min: all.min.map((v, i) => r(v - origin[i])), max: all.max.map((v, i) => r(v - origin[i])) } };
  console.log(`${name}: ${Math.round(tris)} triangles, ${(statSync(`${OUT}${name}.glb`).size / 1e6).toFixed(1)} MB`);
}
writeFileSync(`${OUT}measurements.json`, JSON.stringify(measurements, null, 2) + '\n');
console.log(JSON.stringify(measurements, null, 2));
