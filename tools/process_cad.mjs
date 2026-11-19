// Turns the Onshape export (cad/Robot.glb) into light models the simulator can animate:
//   models/chassis.glb, turret.glb, lever_front.glb, lever_back.glb  +  models/measurements.json
//
//   cd tools && npm install && npm run cad
//
// What it does: drops fasteners, splits the assembly into the moving pieces, rotates/recentres
// everything into the simulator's robot frame (origin on the floor under the drivetrain centre,
// forward = -Z, up = +Y, metres), puts each moving piece's origin on its pivot, and simplifies.
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { dedup, flatten, join, weld, simplify, prune, getBounds } from '@gltf-transform/functions';
import { MeshoptSimplifier } from 'meshoptimizer';
import { writeFileSync, statSync } from 'node:fs';

const SRC = '../cad/Robot.glb';
const OUT = '../models/';
const SIMPLIFY_RATIO = +(process.env.RATIO ?? 0.1);    // keep at most this fraction of triangles
const SIMPLIFY_ERROR = +(process.env.ERROR ?? 0.006);  // allowed shape error (fraction of piece size)
const ONLY = process.argv.slice(2);                    // optional: piece names to rebuild
// Triangle budget per piece, so a finer CAD export does not make the simulator heavier.
const MAX_TRIANGLES = { chassis: 300000, turret: 60000, lever_front: 12000, lever_back: 12000 };
const TINY_PART_M = 0.012;      // parts smaller than this in every direction are dropped

// Names as they appear at the top of the Onshape assembly.
const GROUPS = {
  chassis: [/^Chasis/, /^Support Arm/, /^Intake/, /^Feeder/],
  turret: [/^Torreta/],
  lever_front: [/^Patita </],
  lever_back: [/^Patita-Mirrored/],
};
const FASTENER = /screw|nut\b|nut strip|spacer|washer|standoff|shim|collar|e-clip|retaining|bearing|zip ?tie/i;
// Which end of the robot is "front": -1 = the CAD's -X end (plain "Intake"/"Patita"), +1 = the other.
const FRONT_SIGN = -1;

const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
await MeshoptSimplifier.ready;

const topGroups = (doc) => doc.getRoot().listScenes()[0].listChildren()[0].listChildren();
const disposeTree = (node) => { node.listChildren().forEach(disposeTree); node.dispose(); };
const centre = (b) => b.min.map((v, i) => (v + b.max[i]) / 2);
const findAll = (node, re, out = []) => {
  if (re.test(node.getName()) && node.getMesh()) out.push(node);
  node.listChildren().forEach((c) => findAll(c, re, out));
  return out;
};
const group = (doc, re) => topGroups(doc).filter((n) => re.test(n.getName()));

// ---------- 1. measure the untouched CAD ----------
const cad = await io.read(SRC);
const robotNode = cad.getRoot().listScenes()[0].listChildren()[0];
const wheels = findAll(robotNode, /Mecanum Wheel/i).map((n) => getBounds(n));
if (wheels.length !== 4) throw new Error(`expected 4 mecanum wheels, found ${wheels.length}`);
const wc = wheels.map(centre);
const xs = wc.map((c) => c[0]), zs = wc.map((c) => c[2]);
const mid = (a) => (Math.min(...a) + Math.max(...a)) / 2;
const span = (a) => Math.max(...a) - Math.min(...a);
const origin = [mid(xs), Math.min(...wheels.map((b) => b.min[1])), mid(zs)]; // floor under drivetrain centre
// Wheel axles lie along the short dimension of a wheel's box; the robot rolls along the other one.
const w0 = wheels[0], axleAlongZ = (w0.max[2] - w0.min[2]) < (w0.max[0] - w0.min[0]);
if (!axleAlongZ) throw new Error('wheel axles are not along CAD Z; update the frame conversion');

// CAD -> sim: forward (CAD ∓X) -> -Z, up Y -> Y.
const s = -FRONT_SIGN; // +1 when front is CAD -X
const toSim = (p) => [-s * (p[2] - origin[2]), p[1] - origin[1], s * (p[0] - origin[0])];
const simBounds = (b) => {
  const a = toSim(b.min), c = toSim(b.max);
  return { min: a.map((v, i) => Math.min(v, c[i])), max: a.map((v, i) => Math.max(v, c[i])) };
};

const gear70 = findAll(robotNode, /Spur gear \(70 teeth\)/i)[0];
const turretPivot = toSim(centre(getBounds(gear70)));
turretPivot[1] = 0;
const leverPivot = (re) => {
  const g = group(cad, re)[0];
  const gears = findAll(g, /Spur gear \(30 teeth\)/i).map((n) => centre(getBounds(n)));
  const avg = [0, 1, 2].map((i) => gears.reduce((t, c) => t + c[i], 0) / gears.length);
  return toSim(avg);
};
const pivots = {
  chassis: [0, 0, 0],
  turret: turretPivot,
  lever_front: leverPivot(GROUPS[FRONT_SIGN < 0 ? 'lever_front' : 'lever_back'][0]),
  lever_back: leverPivot(GROUPS[FRONT_SIGN < 0 ? 'lever_back' : 'lever_front'][0]),
};
const all = simBounds(getBounds(robotNode));
// Size without the levers (they may be exported folded out): this is the robot's starting size.
const isLever = (n) => GROUPS.lever_front.concat(GROUPS.lever_back).some((p) => p.test(n.getName()));
const body = topGroups(cad).filter((n) => !isLever(n)).map((n) => simBounds(getBounds(n)));
const stowed = { min: [0, 1, 2].map((i) => Math.min(...body.map((b) => b.min[i]))), max: [0, 1, 2].map((i) => Math.max(...body.map((b) => b.max[i]))) };
// How far each lever is folded out in this export: 0 = upright, 90 = flat, measured at its tip wheels.
const leverAngle = (re, pivot) => {
  const tips = findAll(group(cad, re)[0], /32mm Omni Wheel/i).map((n) => toSim(centre(getBounds(n))));
  if (!tips.length) return 0;
  const tip = [0, 1, 2].map((i) => tips.reduce((t, c) => t + c[i], 0) / tips.length);
  return Math.atan2(Math.abs(tip[2] - pivot[2]), tip[1] - pivot[1]) * 180 / Math.PI;
};
// Which way the shooter points in this export: from the top wheel towards the flywheel, seen from above.
const wheelCentre = (re) => {
  const cs = findAll(robotNode, re).map((n) => toSim(centre(getBounds(n))));
  return cs.length ? [0, 1, 2].map((i) => cs.reduce((t, c) => t + c[i], 0) / cs.length) : null;
};
const fly = wheelCentre(/4in 35A Compliant Wheel/i), topWheel = wheelCentre(/3in 35A Compliant Wheel/i);
// Angle that turns the exported shooting direction onto the turret model's +x (the simulator's convention).
const turretBake = fly && topWheel ? Math.atan2(fly[2] - topWheel[2], fly[0] - topWheel[0]) : 0;
const IN = 0.0254, r = (v, d = 4) => +v.toFixed(d);
const pods = findAll(robotNode, /GB 32mm Omni Wheel/i).map((n) => {
  const b = getBounds(n), c = toSim(centre(b));
  // a pod whose wheel is thin along CAD Z rolls along CAD X = measures forward motion
  return { measures: (b.max[2] - b.min[2]) < (b.max[0] - b.min[0]) ? 'forward' : 'strafe',
    forward_offset_in: r(-c[2] / IN, 3), left_offset_in: r(-c[0] / IN, 3) };
});
const measurements = {
  _note: 'Generated by tools/process_cad.mjs from cad/Robot.glb. Robot frame: origin on the floor under the drivetrain centre, +x right, +y up, -z forward, metres.',
  track_width_in: r(span(zs) / IN, 3),
  wheelbase_in: r(span(xs) / IN, 3),
  size_in: { length: r((stowed.max[2] - stowed.min[2]) / IN, 2), width: r((stowed.max[0] - stowed.min[0]) / IN, 2), height: r(stowed.max[1] / IN, 2) },
  size_note: 'Without the levers, i.e. with them folded up.',
  size_as_exported_in: { length: r((all.max[2] - all.min[2]) / IN, 2), width: r((all.max[0] - all.min[0]) / IN, 2), height: r(all.max[1] / IN, 2) },
  lever_angle_as_exported_deg: { front: r(leverAngle(GROUPS[FRONT_SIGN < 0 ? 'lever_front' : 'lever_back'][0], pivots.lever_front), 1), back: r(leverAngle(GROUPS[FRONT_SIGN < 0 ? 'lever_back' : 'lever_front'][0], pivots.lever_back), 1) },
  turret_home_deg: r(-turretBake * 180 / Math.PI, 1),
  turret_home_note: 'Direction the shooter points in this export, counter-clockwise from the robot\'s right. 90 = straight ahead. The turret model itself is turned so its +x is the shooting direction.',
  shooter: fly && topWheel ? { flywheel_centre_height_m: r(fly[1]), wheel_centre_line_deg: r(Math.atan2(topWheel[1] - fly[1], Math.hypot(topWheel[0] - fly[0], topWheel[2] - fly[2])) * 180 / Math.PI, 2),
    shot_angle_deg: r(90 - Math.atan2(topWheel[1] - fly[1], Math.hypot(topWheel[0] - fly[0], topWheel[2] - fly[2])) * 180 / Math.PI, 2) } : null,
  bounds_m: { min: all.min.map((v) => r(v)), max: all.max.map((v) => r(v)) },
  pivots_m: Object.fromEntries(Object.entries(pivots).map(([k, v]) => [k, v.map((x) => r(x))])),
  odometry_pods: pods,
};

// ---------- 2. write one slim model per moving piece ----------
for (const [name, patterns] of Object.entries(GROUPS)) {
  if (ONLY.length && !ONLY.includes(name)) continue;
  const doc = await io.read(SRC);
  const robot = doc.getRoot().listScenes()[0].listChildren()[0];
  const srcName = (FRONT_SIGN < 0 || !name.startsWith('lever')) ? name : (name === 'lever_front' ? 'lever_back' : 'lever_front');
  const pats = GROUPS[srcName];
  for (const g of robot.listChildren()) if (!pats.some((p) => p.test(g.getName()))) disposeTree(g);
  let before = 0, dropped = 0;
  const strip = (node) => {
    node.listChildren().forEach(strip);
    if (!node.getMesh()) return;
    const b = getBounds(node), size = Math.max(...b.max.map((v, i) => v - b.min[i]));
    if (FASTENER.test(node.getName()) || size < TINY_PART_M) { node.dispose(); dropped++; }
  };
  strip(robot);
  await doc.transform(prune());
  for (const m of doc.getRoot().listMeshes()) for (const p of m.listPrimitives()) before += (p.getIndices() ?? p.getAttribute('POSITION')).getCount() / 3;

  // p_sim = R * (p_cad - origin) - pivot, as a column-major 4x4 on the root node.
  const pv = pivots[name];
  const o = origin;
  const base = [
    0, 0, s, 0,
    0, 1, 0, 0,
    -s, 0, 0, 0,
    s * o[2] - pv[0], -o[1] - pv[1], -s * o[0] - pv[2], 1,
  ];
  if (name === 'turret' && turretBake !== 0) {
    // Turn the turret about its pivot so the shooter points along +x: x' = x cos + z sin, z' = -x sin + z cos.
    const c = Math.cos(turretBake), sn = Math.sin(turretBake);
    for (let col = 0; col < 4; col++) {
      const x = base[col * 4], z = base[col * 4 + 2];
      base[col * 4] = x * c + z * sn;
      base[col * 4 + 2] = -x * sn + z * c;
    }
  }
  robot.setMatrix(base);
  await doc.transform(dedup(), flatten(), join(), weld(),
    simplify({ simplifier: MeshoptSimplifier, ratio: SIMPLIFY_RATIO, error: SIMPLIFY_ERROR }), prune());
  // Still over this piece's triangle budget? Simplify again, allowing a little more shape error each time.
  const count = () => { let n = 0; for (const m of doc.getRoot().listMeshes()) for (const p of m.listPrimitives()) n += (p.getIndices() ?? p.getAttribute('POSITION')).getCount() / 3; return n; };
  for (let pass = 1; pass <= 4 && count() > (MAX_TRIANGLES[name] ?? Infinity); pass++) {
    await doc.transform(simplify({ simplifier: MeshoptSimplifier, ratio: MAX_TRIANGLES[name] / count(), error: SIMPLIFY_ERROR * (1 + pass) }), prune());
  }
  let after = 0;
  for (const m of doc.getRoot().listMeshes()) for (const p of m.listPrimitives()) after += (p.getIndices() ?? p.getAttribute('POSITION')).getCount() / 3;
  doc.getRoot().listScenes()[0].listChildren().forEach((n, i) => n.setName(`${name}_${i}`));
  await io.write(`${OUT}${name}.glb`, doc);
  const mb = statSync(`${OUT}${name}.glb`).size / 1e6;
  console.log(`${name.padEnd(12)} dropped ${String(dropped).padStart(4)} small parts, ${Math.round(before)} -> ${Math.round(after)} triangles, ${mb.toFixed(1)} MB`);
}
writeFileSync(`${OUT}measurements.json`, JSON.stringify(measurements, null, 2) + '\n');
console.log(JSON.stringify(measurements, null, 2));
