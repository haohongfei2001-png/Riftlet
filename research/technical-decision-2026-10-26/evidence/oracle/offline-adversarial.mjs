// Isolated research experiment. No browser, network, application, or user data.
// Evaluates original pinned Oracle functions against Oracle's own FakeDOM fixture.
// Oracle source/fixture: MIT, Copyright (c) 2026 Peter Steinberger; see LICENSE.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { stripTypeScriptTypes } from 'node:module';

const base = path.dirname(fileURLToPath(import.meta.url));
const read = p => fs.readFileSync(path.join(base, p), 'utf8');
const javascript = source => stripTypeScriptTypes(source, {mode: 'transform'})
  .replace(/^import[\s\S]*?;\s*/gm, '')
  .replace(/^export /gm, '');
const load = (p, returns, bindings = {}) => new Function(...Object.keys(bindings), javascript(read(p)) + '\nreturn {' + returns + '};')(...Object.values(bindings));
const {FakeElement, FakeInputElement, FakeDocument} = load('tests/browser/domFixture.ts', 'FakeElement,FakeInputElement,FakeDocument');
const constants = load('src/browser/constants.ts', 'INPUT_SELECTORS,SEND_BUTTON_SELECTORS');
const {buildActiveComposerRootExpression} = load('src/browser/actions/composerRoot.ts', 'buildActiveComposerRootExpression', constants);
const {buildAttachmentEvidenceExpression} = load('src/browser/actions/attachmentEvidence.ts', 'buildAttachmentEvidenceExpression', {buildActiveComposerRootExpression});
const {buildAttachmentProgressExpression} = load('src/browser/actions/attachmentProgress.ts', 'buildAttachmentProgressExpression');
const source = read('src/browser/actions/attachments.ts');
const extract = (begin, end) => source.slice(source.indexOf(begin), source.indexOf(end, source.indexOf(begin)));
const nameFunction = extract('export function buildAttachmentNamePattern(', 'export interface ComposerPlusActivationResult');
const completionFunction = extract('export async function waitForAttachmentCompletion(', 'export async function waitForUserTurnAttachments(');

function fixture({send = true, inputFiles = []} = {}) {
  const form = new FakeElement('form', {'data-testid':'composer'}, [
    new FakeElement('textarea', {id:'prompt-textarea'}),
    new FakeInputElement(inputFiles.map(name => ({name}))),
    ...(send ? [new FakeElement('button', {'data-testid':'send-button'})] : [])
  ]);
  const document = new FakeDocument([form]);
  const renderer = {};
  const evaluate = expression => new Function('document','HTMLElement','HTMLInputElement','window','globalThis','location', 'return ' + expression + ';')(
    document, FakeElement, FakeInputElement,
    {getComputedStyle: () => ({pointerEvents:'auto', opacity:'1', display:'block', visibility:'visible'})},
    renderer, new URL('https://chatgpt.com/c/synthetic-draft')
  );
  const add = (name, state) => {
    const control = new FakeElement('button', {'aria-label':'Remove attachment ' + name});
    form.append(new FakeElement('div', {'data-testid':'attachment-chip', ...(state ? {'data-state':state} : {})}, [control], name));
    return control;
  };
  return {form, document, renderer, evaluate, add};
}

const results = [];
{
  const f = fixture();
  const begin = f.evaluate(buildAttachmentEvidenceExpression(['wanted.png'], 'begin', 'attempt-1'));
  f.add('unrelated-user-added.png');
  const confirmed = f.evaluate(buildAttachmentEvidenceExpression([], 'confirm', 'attempt-1'));
  const wantedReportedPresent = f.evaluate(buildAttachmentEvidenceExpression(['wanted.png']))[0];
  results.push({case:'unique_unrelated_card_claimed_for_requested_asset', begin, confirmed, wantedReportedPresent,
    requestedAssetWasInserted:false, status: wantedReportedPresent ? 'COUNTEREXAMPLE_REPRODUCED':'NOT_REPRODUCED'});
}
async function completionCase(label, fixtureOptions, card) {
  const f = fixture(fixtureOptions);
  if(card) f.add('wanted.png', card.state);
  let clock = 0;
  class FakeDate extends Date {static now(){return clock;}}
  let observations = 0;
  let firstObservation;
  const runtime = {evaluate: async ({expression}) => {
    observations++;
    const value = f.evaluate(expression);
    firstObservation ??= value;
    return {result:{value}};
  }};
  const bindings = {...constants, buildAttachmentEvidenceExpression, buildAttachmentProgressExpression,
    Date:FakeDate, delay:async ms=>{clock += ms;}, logDomFailure:async()=>{}};
  const {waitForAttachmentCompletion} = new Function(...Object.keys(bindings), javascript(nameFunction + completionFunction) + '\nreturn {waitForAttachmentCompletion};')(...Object.values(bindings));
  let resolved = false, error;
  try {await waitForAttachmentCompletion(runtime, 4000, ['wanted.png']); resolved = true;}
  catch(e){error = e.message;}
  results.push({case:label, fixture:{...fixtureOptions, card}, resolved, error, elapsedSimulatedMs:clock, observations, firstObservation,
    status:resolved ? 'COUNTEREXAMPLE_REPRODUCED':'NOT_REPRODUCED'});
}
await completionCase('file_input_only_no_card_no_send_button', {send:false, inputFiles:['wanted.png']});
await completionCase('explicit_error_card_send_enabled', {send:true}, {state:'error'});
await completionCase('card_exists_send_button_absent_no_ready_signal', {send:false}, {});

const report = {scope:'OFFLINE_FIXTURE_ONLY; NOT a ChatGPT or macOS integration test',
  sourceCommit:'fde96271db1611c0287fcfde3053c19325280d10', runtime:process.version,
  fixtureSource:'tests/browser/domFixture.ts (unchanged original source, TypeScript-transpiled in memory)',
  functionSource:'attachmentEvidence.ts and waitForAttachmentCompletion in attachments.ts (original logic)',
  resultCount:results.length, results};
fs.writeFileSync(path.join(base,'offline-adversarial-results.json'), JSON.stringify(report, null, 2)+'\n');
console.log(JSON.stringify(report, null, 2));
