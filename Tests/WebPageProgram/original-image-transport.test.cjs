'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {fixture, png} = require('./independent-input-fixture.cjs');

// A generated 4 × 4 JPEG. Length-delimited APP15 segments below are part of
// the original file, so an exact byte assertion also covers every chunk edge.
const jpeg = Buffer.from('/9j/4AAQSkZJRgABAQAASABIAAD/4QBMRXhpZgAATU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMAAAABAAEAAKACAAQAAAABAAAABKADAAQAAAABAAAABAAAAAD/7QA4UGhvdG9zaG9wIDMuMAA4QklNBAQAAAAAAAA4QklNBCUAAAAAABDUHYzZjwCyBOmACZjs+EJ+/8AAEQgABAAEAwEiAAIRAQMRAf/EAB8AAAEFAQEBAQEBAAAAAAAAAAABAgMEBQYHCAkKC//EALUQAAIBAwMCBAMFBQQEAAABfQECAwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYXGBkaJSYnKCkqNDU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6g4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2drh4uPk5ebn6Onq8fLz9PX29/j5+v/EAB8BAAMBAQEBAQEBAQEAAAAAAAABAgMEBQYHCAkKC//EALURAAIBAgQEAwQHBQQEAAECdwABAgMRBAUhMQYSQVEHYXETIjKBCBRCkaGxwQkjM1LwFWJy0QoWJDThJfEXGBkaJicoKSo1Njc4OTpDREVGR0hJSlNUVVZXWFlaY2RlZmdoaWpzdHV2d3h5eoKDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uLj5OXm5+jp6vLz9PX29/j5+v/bAEMAAgICAgICAwICAwUDAwMFBgUFBQUGCAYGBgYGCAoICAgICAgKCgoKCgoKCgwMDAwMDA4ODg4ODw8PDw8PDw8PD//bAEMBAgICBAQEBwQEBxALCQsQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEP/dAAQAAf/aAAwDAQACEQMRAD8A+iKKKK+4Pjz/2Q==', 'base64');
const segment = Buffer.alloc(65537, 0x61);
segment.set([0xff, 0xef, 0xff, 0xff]);
const largeJPEG = Buffer.concat([jpeg.subarray(0, 2), ...Array(129).fill(segment), jpeg.subarray(2)]);

test('original PNG and a JPEG over 8 MiB each reach the actual receiver with their MIME, bytes and START', async () => {
  const page = fixture(), files = [];
  page.setChange(file => files.push(file));
  for (const [bytes, mime, ext] of [[png, 'image/png', 'png'], [largeJPEG, 'image/jpeg', 'jpg']]) {
    const op = page.bind({bytes}), name = 'riftlet-' + op.identity.operationID + '.' + ext;
    page.call({...op.command('begin'), uploadName: name, mediaType: mime, byteCount: bytes.length});
    let index = 0;
    for (let offset = 0; offset < bytes.length; offset += 256 * 1024) {
      page.call({...op.command('chunk'), chunkIndex: index++,
        chunkBase64: bytes.subarray(offset, offset + 256 * 1024).toString('base64')});
    }
    const result = await page.call({...op.command('commit'), chunkIndex: index});
    assert.equal(result.observation.state, 'uploadStarted');
    const received = files.at(-1);
    assert.equal(received.name, name); assert.equal(received.type, mime);
    assert.deepEqual(Buffer.from(await received.arrayBuffer()), bytes);
  }
  assert.ok(largeJPEG.length > 8 * 1024 * 1024);
  assert.equal(page.setters, 2); assert.equal(page.changes, 2); assert.equal(page.sends, 0);
});
