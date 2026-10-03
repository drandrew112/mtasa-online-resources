// MTA heading math (mirrors shared/math.lua of the bridge).
// heading = MTA rotation.z in degrees: 0 = north (+Y), 90 = west (-X), 180 = south, 270 = east.

const RAD = Math.PI / 180;

export const norm = (a) => ((a % 360) + 360) % 360;

export function angleDiff(a, b) {
  let d = norm(b) - norm(a);
  if (d > 180) d -= 360;
  else if (d <= -180) d += 360;
  return d;
}

export const forward = (h) => [-Math.sin(h * RAD), Math.cos(h * RAD)];
export const right = (h) => [Math.cos(h * RAD), Math.sin(h * RAD)];

export function headingFromVector(dx, dy) {
  if (dx === 0 && dy === 0) return 0;
  return norm(Math.atan2(-dx, dy) / RAD);
}

export const headingTo = (x1, y1, x2, y2) => headingFromVector(x2 - x1, y2 - y1);

const COMPASS = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
export function compass(h) {
  const bearing = norm(360 - norm(h));
  return COMPASS[Math.floor((bearing + 22.5) / 45) % 8];
}

export const dist2 = (ax, ay, bx, by) => Math.hypot(bx - ax, by - ay);
export const dist3 = (ax, ay, az, bx, by, bz) => Math.hypot(bx - ax, by - ay, (bz ?? 0) - (az ?? 0));

export const round = (v, d = 3) => {
  const m = 10 ** d;
  return Math.round(v * m) / m;
};

export const vec = (x, y, z, d = 3) => ({ x: round(x, d), y: round(y, d), z: round(z ?? 0, d) });

// point -> {x,y,z} from {x,y,z} | [x,y,z]
export function toPoint(p) {
  if (!p) return null;
  if (Array.isArray(p)) return { x: Number(p[0]), y: Number(p[1]), z: p[2] === undefined ? undefined : Number(p[2]) };
  if (typeof p === 'object' && p.x !== undefined && p.y !== undefined) return { x: Number(p.x), y: Number(p.y), z: p.z === undefined ? undefined : Number(p.z) };
  return null;
}

// signed lateral offset of point P from line A->B (+ = right of travel), and projection t
export function projectOnSegment(ax, ay, bx, by, px, py) {
  const vx = bx - ax, vy = by - ay;
  const l2 = vx * vx + vy * vy;
  let t = l2 > 0 ? ((px - ax) * vx + (py - ay) * vy) / l2 : 0;
  t = Math.max(0, Math.min(1, t));
  const qx = ax + vx * t, qy = ay + vy * t;
  const h = headingFromVector(vx, vy);
  const [rx, ry] = right(h);
  const lateral = (px - qx) * rx + (py - qy) * ry;
  return { t, x: qx, y: qy, distance: Math.hypot(px - qx, py - qy), lateral, heading: h };
}
