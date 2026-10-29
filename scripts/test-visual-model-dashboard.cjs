// Exercise the actual dashboard functions without a browser or model runtime.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const source = fs.readFileSync('assets/dashboard/dashboard.js', 'utf8');
const nodes = new Map();
const node = (id) => {
  if (!nodes.has(id)) nodes.set(id, {value: '', options: [], replaceChildren() { this.options = []; }, append(option) { this.options.push(option); }});
  return nodes.get(id);
};
let resolvePreview;
let calls = 0;
const context = vm.createContext({
  state: {}, byId: node, document: {createElement: () => ({})},
  lifecycle: () => {}, dataOf: (value) => value,
  callSoul: () => { calls++; return new Promise((resolve) => { resolvePreview = resolve; }); },
});
for (const name of ['visualProjectInput', 'renderVisualModelChoices', 'invalidateVisualApproval', 'previewVisualGeneration']) {
  const start = source.indexOf(`${name === 'previewVisualGeneration' ? 'async ' : ''}function ${name}(`);
  assert.ok(start >= 0);
  const end = source.indexOf('\n}\n', start) + 2;
  vm.runInContext(source.slice(start, end), context);
}
(async () => {
  context.state.visualDefaultProfile = 'distilled';
  context.state.visualProfileChoices = [{id:'distilled', label:'Distilled', enabled:true}, {id:'base', label:'Base', enabled:false, reason:'Pacing pending'}];
  context.renderVisualModelChoices();
  assert.equal(node('visual-profile').value, 'distilled');
  assert.equal(node('visual-profile').options[1].disabled, true);
  context.state.selectedVisualProject = {profile_id:'legacy'};
  context.renderVisualModelChoices();
  assert.equal(node('visual-profile').value, 'legacy');
  assert.equal(node('visual-profile').options.at(-1).disabled, true);
  node('visual-profile').value = 'distilled';
  context.state.selectedVisualProject = {...context.visualProjectInput(), project_id:'fixture'};
  const pending = context.previewVisualGeneration();
  assert.equal(calls, 1);
  node('visual-profile').value = 'base';
  context.invalidateVisualApproval();
  resolvePreview({expected_digest:'old'});
  await pending;
  assert.equal(context.state.visualPreview, null);
  assert.equal(node('start-visual-generation').disabled, true);
  await context.previewVisualGeneration();
  assert.equal(calls, 1, 'unsaved model change must not request approval');
  node('visual-profile').value = 'distilled';
  const fresh = context.previewVisualGeneration();
  resolvePreview({expected_digest:'fresh'});
  await fresh;
  assert.equal(context.state.visualPreview.expected_digest, 'fresh');
  assert.equal(node('start-visual-generation').disabled, false);
  console.log('Visual model dashboard: selection, historical preservation, stale response and unsaved-change checks passed');
})().catch((error) => { console.error(error); process.exitCode = 1; });
