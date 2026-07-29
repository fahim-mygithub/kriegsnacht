'use strict';

/* Minimal 8-bit RGBA PNG codec, written here rather than pulled from npm.
 *
 * Encoding: the ancestor's bake() hands back a Uint32Array aliased onto an
 * ImageData buffer, which on a little-endian machine is already the exact byte
 * order a colour-type-6 PNG scanline wants. Going out through
 * canvas.encode('png') instead would mean a getImageData -> putImageData round
 * trip through Skia's premultiplied storage, and premultiplication is lossy at
 * the antialiased sprite edges that outlineSprite() thresholds on — so the one
 * place the pipeline could gain error is the one place it must not.
 *
 * Decoding exists so --check can compare *pixels* against the committed PNGs.
 * File bytes are not comparable: every committed asset carries Chromium's IDAT
 * chunking (4096-byte splits and a 6-byte tail), which is a property of the
 * encoder that produced them, not of the image. */

const zlib = require('zlib');

const SIG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

const CRC_TABLE = (() => {
	const t = new Int32Array(256);
	for (let n = 0; n < 256; n++) {
		let c = n;
		for (let k = 0; k < 8; k++) c = (c & 1) ? (0xedb88320 ^ (c >>> 1)) : (c >>> 1);
		t[n] = c;
	}
	return t;
})();


function crc32(buf) {
	let c = -1;
	for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
	return (c ^ -1) >>> 0;
}


function chunk(type, data) {
	const out = Buffer.alloc(12 + data.length);
	out.writeUInt32BE(data.length, 0);
	out.write(type, 4, 'latin1');
	data.copy(out, 8);
	out.writeUInt32BE(crc32(out.subarray(4, 8 + data.length)), 8 + data.length);
	return out;
}


/* `rgba` is w*h*4 bytes, row-major, non-premultiplied — exactly ImageData. */
function encode(w, h, rgba) {
	if (rgba.length !== w * h * 4) {
		throw new Error(`png.encode: expected ${w * h * 4} bytes for ${w}x${h}, got ${rgba.length}`);
	}
	// Filter type 0 (None) on every scanline. The images are tiny and mostly
	// flat colour, so the adaptive filters buy a few hundred bytes at the cost
	// of making the output depend on a heuristic.
	const raw = Buffer.alloc(h * (1 + w * 4));
	for (let y = 0; y < h; y++) {
		raw[y * (1 + w * 4)] = 0;
		Buffer.from(rgba.buffer, rgba.byteOffset + y * w * 4, w * 4)
			.copy(raw, y * (1 + w * 4) + 1);
	}
	const ihdr = Buffer.alloc(13);
	ihdr.writeUInt32BE(w, 0);
	ihdr.writeUInt32BE(h, 4);
	ihdr[8] = 8;    // bit depth
	ihdr[9] = 6;    // colour type: truecolour with alpha
	ihdr[10] = 0;   // deflate
	ihdr[11] = 0;   // adaptive filtering
	ihdr[12] = 0;   // no interlace
	return Buffer.concat([
		SIG,
		chunk('IHDR', ihdr),
		chunk('IDAT', zlib.deflateSync(raw, { level: 9 })),
		chunk('IEND', Buffer.alloc(0)),
	]);
}


function paeth(a, b, c) {
	const p = a + b - c;
	const pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
	if (pa <= pb && pa <= pc) return a;
	return pb <= pc ? b : c;
}


/* Returns {w, h, rgba}. Only the shape every asset in this repo uses is
 * supported; anything else throws rather than guessing. */
function decode(buf) {
	if (!buf.subarray(0, 8).equals(SIG)) throw new Error('png.decode: not a PNG');
	let off = 8, ihdr = null;
	const idat = [];
	while (off < buf.length) {
		const len = buf.readUInt32BE(off);
		const type = buf.toString('latin1', off + 4, off + 8);
		const data = buf.subarray(off + 8, off + 8 + len);
		if (type === 'IHDR') ihdr = data;
		else if (type === 'IDAT') idat.push(data);
		else if (type === 'IEND') break;
		off += 12 + len;
	}
	if (!ihdr) throw new Error('png.decode: no IHDR');
	const w = ihdr.readUInt32BE(0), h = ihdr.readUInt32BE(4);
	const depth = ihdr[8], colour = ihdr[9], interlace = ihdr[12];
	if (depth !== 8 || colour !== 6 || interlace !== 0) {
		throw new Error(`png.decode: unsupported (depth ${depth}, colour ${colour}, interlace ${interlace}); ` +
			'this codec handles 8-bit RGBA non-interlaced only');
	}
	const raw = zlib.inflateSync(Buffer.concat(idat));
	const stride = w * 4;
	const out = Buffer.alloc(h * stride);
	for (let y = 0; y < h; y++) {
		const filter = raw[y * (stride + 1)];
		const src = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1));
		const cur = out.subarray(y * stride, (y + 1) * stride);
		const prev = y > 0 ? out.subarray((y - 1) * stride, y * stride) : null;
		for (let i = 0; i < stride; i++) {
			const a = i >= 4 ? cur[i - 4] : 0;
			const b = prev ? prev[i] : 0;
			const c = (prev && i >= 4) ? prev[i - 4] : 0;
			let v = src[i];
			if (filter === 1) v += a;
			else if (filter === 2) v += b;
			else if (filter === 3) v += (a + b) >> 1;
			else if (filter === 4) v += paeth(a, b, c);
			else if (filter !== 0) throw new Error(`png.decode: bad filter ${filter} on row ${y}`);
			cur[i] = v & 0xff;
		}
	}
	return { w, h, rgba: out };
}


module.exports = { encode, decode };
