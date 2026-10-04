// Synthesises the short train sounds (no recordings needed):
//   sounds/clack.wav  - wheel over a rail joint (two metallic knocks, front + rear axle)
//   sounds/squeal.wav - flange squeal in tight curves (loop)
//   node tools/gen_sounds.js
const fs = require('fs');
const path = require('path');

const RATE = 22050;

function wav(name, samples) {
    const data = Buffer.alloc(samples.length * 2);
    samples.forEach((v, i) => data.writeInt16LE(Math.max(-32767, Math.min(32767, Math.round(v * 32767))), i * 2));
    const h = Buffer.alloc(44);
    h.write('RIFF', 0); h.writeUInt32LE(36 + data.length, 4); h.write('WAVE', 8);
    h.write('fmt ', 12); h.writeUInt32LE(16, 16); h.writeUInt16LE(1, 20); h.writeUInt16LE(1, 22);
    h.writeUInt32LE(RATE, 24); h.writeUInt32LE(RATE * 2, 28); h.writeUInt16LE(2, 32); h.writeUInt16LE(16, 34);
    h.write('data', 36); h.writeUInt32LE(data.length, 40);
    const out = path.join(__dirname, '..', 'sounds', name);
    fs.mkdirSync(path.dirname(out), { recursive: true });
    fs.writeFileSync(out, Buffer.concat([h, data]));
    console.log('written', out, samples.length / RATE, 's');
}

// seeded noise so the files are reproducible
let seed = 12345;
const rnd = () => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed / 0x7fffffff * 2 - 1; };

// clack: knock = noise burst + low "thud" + ringing partials, exponential decay; second knock 120 ms later
function knock(buf, at, gain) {
    const n = Math.floor(0.18 * RATE);
    let lp = 0;
    for (let i = 0; i < n && at + i < buf.length; i++) {
        const t = i / RATE;
        lp += (rnd() - lp) * 0.35;                       // darker noise
        const env = Math.exp(-t * 38);
        const ring = Math.sin(2 * Math.PI * 1150 * t) * 0.25 + Math.sin(2 * Math.PI * 2310 * t) * 0.12;
        const thud = Math.sin(2 * Math.PI * 95 * t) * Math.exp(-t * 22) * 0.7;
        buf[at + i] += gain * (lp * 0.9 * env + ring * Math.exp(-t * 55) + thud);
    }
}
{
    const buf = new Array(Math.floor(0.42 * RATE)).fill(0);
    knock(buf, 0, 0.75);
    knock(buf, Math.floor(0.12 * RATE), 0.6);
    wav('clack.wav', buf);
}

// squeal: wavering high tone (2.9-3.3 kHz) with harmonics and some noise; seamless 2 s loop
{
    const len = 2 * RATE;
    const buf = new Array(len).fill(0);
    let phase = 0;
    for (let i = 0; i < len; i++) {
        const t = i / RATE;
        const f = 3100 + 200 * Math.sin(2 * Math.PI * 1.5 * t) + 60 * Math.sin(2 * Math.PI * 7 * t);
        phase += 2 * Math.PI * f / RATE;
        const amp = 0.55 + 0.3 * Math.sin(2 * Math.PI * 2 * t) ** 2;
        buf[i] = amp * (Math.sin(phase) * 0.6 + Math.sin(2 * phase) * 0.15) + rnd() * 0.05;
    }
    // fade the loop seam
    const fade = Math.floor(0.02 * RATE);
    for (let i = 0; i < fade; i++) { const g = i / fade; buf[i] *= g; buf[len - 1 - i] *= g; }
    wav('squeal.wav', buf.map(v => v * 0.6));
}
