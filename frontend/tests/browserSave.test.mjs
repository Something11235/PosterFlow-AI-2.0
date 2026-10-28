import assert from "node:assert/strict";
import { afterEach, mock, test } from "node:test";
import { saveBrowserFile } from "../src/lib/browserSave.js";
import { readImageRelay, IMAGE_RELAY_CHUNK_BYTES as SIZE } from "../src/lib/imageRelay.js";

globalThis.window = {};
afterEach(() => { mock.restoreAll(); delete window.showSaveFilePicker; });

test("browser saves exact bytes through native picker without any download-manager anchor", async () => {
  const order = [];
  const data = new Blob(["original bytes"]);
  window.showSaveFilePicker = async ({ suggestedName }) => {
    assert.equal(suggestedName, "one.png"); order.push("picker");
    return { createWritable: async () => ({ write: async blob => { assert.equal(blob, data); order.push("write"); }, close: async () => order.push("close") }) };
  };
  assert.equal(await saveBrowserFile("one.png", async () => { order.push("read"); return data; }), "saved");
  assert.deepEqual(order, ["picker", "read", "write", "close"]);
});

test("cancelled picker does not read the image or create a file", async () => {
  window.showSaveFilePicker = async () => { throw new DOMException("cancel", "AbortError"); };
  assert.equal(await saveBrowserFile("one.png", () => assert.fail("no read on cancellation")), "cancelled");
});

test("write errors abort incomplete output and never report success", async () => {
  let aborted = false;
  window.showSaveFilePicker = async () => ({ createWritable: async () => ({ write: async () => { throw new Error("disk full"); }, abort: async () => { aborted = true; } }) });
  await assert.rejects(saveBrowserFile("one.png", async () => new Blob(["a"])), /disk full/);
  assert.equal(aborted, true);
});

test("unsupported browsers keep the standard browser download fallback", async () => {
  const link = { click: mock.fn(), remove: mock.fn() };
  mock.method(globalThis, "setTimeout", callback => { callback(); return 1; });
  window.setTimeout = globalThis.setTimeout;
  globalThis.document = { createElement: () => link, body: { appendChild() {} } };
  assert.equal(await saveBrowserFile("one.png", async () => new Blob(["image"])), "requested");
  assert.equal(link.download, "one.png");
  assert.match(link.href, /^blob:/);
  assert.equal(link.click.mock.callCount(), 1);
  delete globalThis.document;
});

const PNG = new Uint8Array(SIZE + 23); PNG.set([137,80,78,71,13,10,26,10]);
const timed = (fn) => fn(new AbortController().signal);
test("relay reconstructs originals in bounded requests with owner authentication and version checks", async () => {
  const calls = [];
  mock.method(globalThis, "fetch", async (url, init) => {
    const start = Number(url.split("offset=")[1]); calls.push(start);
    assert.equal(init.headers.Authorization, "Bearer user-a");
    assert.equal(init.credentials, "include");
    if (start) assert.equal(init.headers["X-Image-Version"], '"v1"');
    return new Response(PNG.slice(start, start + SIZE), { headers: { "X-Image-Size": String(PNG.length), "X-Image-Offset": String(start), ETag: '"v1"' } });
  });
  const blob = await readImageRelay("one.png", { Authorization: "Bearer user-a" }, timed);
  assert.deepEqual(new Uint8Array(await blob.arrayBuffer()), PNG);
  assert.deepEqual(calls, [0, SIZE]);
});

test("relay rejects changing objects, incomplete chunks and oversized metadata", async () => {
  for (const mode of ["changed", "short", "oversized", "bad-png"]) {
    mock.method(globalThis, "fetch", async url => {
      const start = Number(url.split("offset=")[1]);
      const part = PNG.slice(start, start + SIZE - (mode === "short" ? 1 : 0));
      if (mode === "bad-png") part.fill(0);
      return new Response(part, { headers: { "X-Image-Size": String(mode === "oversized" ? 99 * SIZE : PNG.length), "X-Image-Offset": String(start), ETag: mode === "changed" && start ? '"v2"' : '"v1"' } });
    });
    await assert.rejects(readImageRelay("one.png", {}, timed), /原图/);
    mock.restoreAll();
  }
});
