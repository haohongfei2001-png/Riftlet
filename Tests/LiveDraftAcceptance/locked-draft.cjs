'use strict';

const {beginDraft,withCleanup} = require('./internal/draft-workflow.cjs');

// Populate only with reviewed, module-owned implementations. Each must
// verify its supported backend/version and enforce the native+document+editor
// generation at delivery for navigation, clicks, keys, selection and cleanup.
// Neither current Browser tab API supplies that operation.
const reviewedAdapters = Object.freeze([]);

async function resolveOriginalDocumentAdapter(browser, bundle) {
  for (const adapter of reviewedAdapters) {
    if (await adapter.supports(browser,bundle)) return adapter;
  }
  const error = new Error('ORIGINAL_DOCUMENT_KEYBOARD_UNAVAILABLE');
  error.code = error.message;
  error.status = 'BLOCKED';
  error.cleanup = 'none';
  throw error;
}

async function createLockedDraft(options) {
  const adapter = await resolveOriginalDocumentAdapter(options.browser,options.bundle);
  return beginDraft(options,adapter);
}

async function withLockedDraft(options, execute) {
  return withCleanup(await createLockedDraft(options),execute);
}

module.exports = {createLockedDraft,withLockedDraft};
