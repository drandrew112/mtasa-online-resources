import test from 'node:test';
import assert from 'node:assert/strict';
import { RoadGraph } from '../src/roads/graph.js';
import { config } from '../src/config.js';
import { headingTo, compass, projectOnSegment } from '../src/geo.js';

const g = new RoadGraph().load(config.vehicleNodesPath);

test('loads every node', () => {
  const s = g.stats();
  assert.equal(s.nodes, 30586);
  assert.ok(s.segments > 30000);
  assert.ok(s.intersections > 100);
});

test('node 65915 matches the file', () => {
  const n = g.get(65915);
  assert.equal(n.x, -1683.25);
  assert.equal(n.y, -2289.75);
  assert.ok(n.adj.has(65914) && n.adj.has(65916));
});

test('nearest node / segment', () => {
  const [r] = g.nearestNodes(-1683, -2289, 40);
  assert.equal(r.node.id, 65915);
  const [s] = g.nearestSegments(-1683, -2289, 40);
  assert.ok(s.distance < 2);
});

test('path between connected nodes', () => {
  const p = g.path(65915, 65564);
  assert.ok(p.found);
  assert.equal(p.nodes[0], 65915);
  assert.equal(p.nodes.at(-1), 65564);
});

test('geo conventions', () => {
  assert.equal(headingTo(0, 0, 0, 10), 0);
  assert.equal(headingTo(0, 0, -10, 0), 90);
  assert.equal(compass(270), 'E');
  const p = projectOnSegment(0, 0, 0, 10, 2, 5); // heading north, point east = right
  assert.ok(p.lateral > 1.99);
});
