// Executable observation model, NOT a browser/WindowServer event recording.
// It demonstrates what incomplete observations cannot distinguish. It does not
// claim an installed, lossless browser activation journal has these observations.
import assert from 'node:assert/strict';

const eventAt = 10;
const nativeEvent = {at: eventAt, receiver: 'Riftlet input island', button: 0,
  foregroundProcess: 'same Chrome process'};
const history = [
  {at: 5, observed: {pageWitness: 'A', generation: 1}},
  {at: 6, observed: {lastNativeWindow: 'window-A', lastNativeTab: 'tab-A'}},
  {at: eventAt, observed: nativeEvent},
  {at: 12, observed: {currentNativeWindow: 'window-A', currentNativeTab: 'tab-A'}}
];
const stable = {actualTargetAtEvent: 'draft-A', observations: history};
const switched = {actualTargetAtEvent: 'draft-B', observations: structuredClone(history),
  unobserved: [
    {at: 9, active: 'window-B / tab-B / draft-B'},
    {at: 11, active: 'window-A / tab-A / draft-A'}
  ]};
assert.deepEqual(stable.observations, switched.observations);
assert.notEqual(stable.actualTargetAtEvent, switched.actualTargetAtEvent);
// Enumerate the modeled target choices and refusal for this identical input.
// A and B are each wrong in one history; only refusal is safe in both.
const safeInBoth = ['draft-A', 'draft-B', 'REFUSE'].filter(choice =>
  [stable, switched].every(trace => choice === 'REFUSE' || choice === trace.actualTargetAtEvent));
assert.deepEqual(safeInBoth, ['REFUSE']);

// Even an ideal clock mapping that proves an earlier page witness does not
// supply the missing window/tab-at-native-event relation.
const pageWitnessTime = 4, clockOffsetInterval = [0.5, 1.5];
assert(pageWitnessTime + clockOffsetInterval[1] < eventAt);
assert.deepEqual(stable.observations, switched.observations);

// A later current-state query cannot reconstruct the original business draft.
// The first world changes A -> B after the event, before the query executes.
const lateCurrentRead = {queryDispatchedAt: 10.1, queryExecutedAt: 12, target: 'draft-B'};
const afterA = {targetAtEvent: 'draft-A', read: lateCurrentRead};
const alreadyB = {targetAtEvent: 'draft-B', read: structuredClone(lateCurrentRead)};
assert.deepEqual(afterA.read, alreadyB.read);
assert.notEqual(afterA.targetAtEvent, alreadyB.targetAtEvent);

// URL/document endpoint equality is insufficient when business continuity was
// never observed. This is NOT a claim that v13 fails to see its monitored ABA.
const endpoints = [{at: 5, document: 'doc', url: '/c/example', draft: 'A'},
  {at: 12, document: 'doc', url: '/c/example', draft: 'A'}];
const unchanged = {endpoints, generationAtEvent: 1};
const unmonitoredABA = {endpoints: structuredClone(endpoints), generationAtEvent: 3};
assert.deepEqual(unchanged.endpoints, unmonitoredABA.endpoints);
assert.notEqual(unchanged.generationAtEvent, unmonitoredABA.generationAtEvent);

console.log(JSON.stringify({result: 'PASS', scope: 'EXECUTABLE_INCOMPLETE_OBSERVATION_MODEL',
  liveBrowserEvents: 0, physicalInputs: 0, uploadInputs: 0, productionAuthority: false,
  cases: ['same_native_observations_different_click_time_target',
    'pre_event_page_clock_bound_does_not_prove_native_event_owner',
    'late_current_query_does_not_reconstruct_original_target',
    'unmonitored_business_ABA_is_not_endpoint_continuity'],
  onlyDecisionSafeInBothModeledNativeHistories: safeInBoth,
  excludedClaims: ['not_a_lossless_journal_impossibility_proof',
    'not_a_measured_macOS_event_schedule', 'not_a_v13_monitored_ABA_failure']}, null, 2));
