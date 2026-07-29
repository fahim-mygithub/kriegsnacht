/* The whole DOM surface the ancestor's drawing code touches.
 *
 * kriegsnacht.html calls `document.createElement('canvas')` exactly once, in
 * makeCanvas() at html:565, and sets .width/.height on the result immediately
 * afterwards — so a factory returning a 1x1 canvas is enough. Everything else
 * in the extracted ranges is plain Canvas2D. See R7 §A2, which measured this
 * shim reproducing the committed zombie strip to a mean delta of 2.7/255.
 *
 * @napi-rs/canvas is Skia, the same rasteriser Chrome uses, which is why the
 * residual is antialiasing noise rather than a different drawing. */
const { createCanvas } = require('@napi-rs/canvas');
const document = { createElement: () => createCanvas(1, 1) };

/* Not part of the DOM shim: the deterministic replacement for the CSS fonts
 * the ancestor draws text with. extract.js rewrites all five `fillText` sites
 * to call FONT.text(); see PATCHES there for the list and the reasoning. */
const FONT = require('./font5x7.js');
