// Generates sounds/chime.wav: the two-tone station announcement gong (node tools/gen_sounds.js)
const fs = require('fs'), path = require('path');
const RATE = 22050;

function wav(samples) {
    const b = Buffer.alloc(44 + samples.length * 2);
    b.write('RIFF', 0); b.writeUInt32LE(36 + samples.length * 2, 4); b.write('WAVE', 8);
    b.write('fmt ', 12); b.writeUInt32LE(16, 16); b.writeUInt16LE(1, 20); b.writeUInt16LE(1, 22);
    b.writeUInt32LE(RATE, 24); b.writeUInt32LE(RATE * 2, 28); b.writeUInt16LE(2, 32); b.writeUInt16LE(16, 34);
    b.write('data', 36); b.writeUInt32LE(samples.length * 2, 40);
    samples.forEach((s, i) => b.writeInt16LE(Math.max(-32767, Math.min(32767, Math.round(s * 32767))), 44 + i * 2));
    return b;
}

// a soft bell: fundamental + a few inharmonic partials, exponential decay
function bell(out, start, f, dur, amp) {
    const partials = [[1, 1], [2.0, 0.35], [2.76, 0.18], [5.4, 0.06]];
    for (let i = 0; i < dur * RATE; i++) {
        const t = i / RATE, env = Math.min(1, t / 0.01) * Math.exp(-t * 2.6);
        let s = 0;
        for (const [m, a] of partials) s += a * Math.sin(2 * Math.PI * f * m * t) * Math.exp(-t * m * 0.8);
        const k = Math.floor(start * RATE) + i;
        if (k < out.length) out[k] += s * env * amp;
    }
}

const out = new Float64Array(Math.floor(2.4 * RATE));
bell(out, 0.0, 659.25, 2.0, 0.32);   // E5
bell(out, 0.45, 523.25, 1.9, 0.32);  // C5
fs.writeFileSync(path.join(__dirname, '..', 'sounds', 'chime.wav'), wav(Array.from(out)));
console.log('sounds/chime.wav written');
