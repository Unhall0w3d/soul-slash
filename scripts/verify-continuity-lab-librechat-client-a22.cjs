#!/usr/bin/env node
'use strict';

// Installed client formatter/parser against the actual Ruby application via
// fake fetch. No DNS, socket, credential, LibreChat data or service is used.
const {createRequire} = require('node:module');
const {execFileSync} = require('node:child_process');
const path = require('node:path');
const assert = require('node:assert/strict');
const installed = createRequire('/usr/lib/librechat/package.json');
const {ChatOpenAI} = installed('@langchain/openai');
const {HumanMessage, AIMessage} = installed('@langchain/core/messages');
const fixtureToken = 'synthetic-a22-not-a-credential-000000';
const modelName = 'soul-continuity-qwen';
const ruby = '/home/bhones/.rbenv/versions/4.0.7/bin/ruby';
const app = path.resolve(__dirname, '../lib/soul_core/continuity_lab/chat_application');
const driver = `require 'json'; require ARGV.fetch(0)
lab = SoulCore::ContinuityLab
backend = Object.new
def backend.complete(conversation_id:, messages:)
  {'id'=>'chatcmpl-synthetic', 'created'=>0, 'content'=>"A quoted \\"reply\\" with café and a newline.\\nDone.", 'soul'=>{'fixture'=>true}}
end
request = JSON.parse(STDIN.read)
response = lab::ChatApplication.new(backend: backend, bearer_token: '${fixtureToken}').call(
  method: request.fetch('method'), target: URI(request.fetch('url')).path,
  headers: request.fetch('headers'), body: request.fetch('body').b)
STDOUT.write(JSON.generate({'status'=>response.status,'headers'=>response.headers,'body'=>response.body}))
`;
let fetches = 0;
const requests = [];
const fakeFetch = async (input, init) => {
  fetches++;
  requests.push(JSON.parse(init.body));
  const serialized = {url: String(input), method: init.method,
    headers: Object.fromEntries(new Headers(init.headers).entries()), body: init.body};
  const result = JSON.parse(execFileSync(ruby, ['-ruri', '-e', driver, app], {
    input: JSON.stringify(serialized), encoding: 'utf8', timeout: 10000, maxBuffer: 1024 * 1024
  }));
  assert.equal(result.status, 200);
  return new Response(result.body, {status: result.status, headers: result.headers});
};

(async () => {
  const model = new ChatOpenAI({model: modelName, apiKey: fixtureToken,
    streaming: true, streamUsage: false, maxTokens: 768, temperature: 0.6,
    topP: 0.95, maxRetries: 0, timeout: 10000, configuration: {
      baseURL: 'http://soul.invalid/v1', fetch: fakeFetch,
      defaultHeaders: {'X-Soul-Conversation-Id': 'a22-synthetic-conversation'}
    }});
  let text = '';
  for await (const chunk of await model.stream([
    new HumanMessage('Synthetic café question.'), new AIMessage('Synthetic prior reply.'),
    new HumanMessage('Synthetic follow-up.')
  ])) text += chunk.content;
  assert.equal(text, 'A quoted "reply" with café and a newline.\nDone.');
  assert.equal(fetches, 1);
  assert.deepEqual(Object.keys(requests[0]).sort(), ['max_tokens','messages','model','stream','temperature','top_p']);
  assert.equal(requests[0].messages[0].content, 'Synthetic café question.');
  assert.equal(requests[0].messages.at(-1).role, 'user');
  process.stdout.write(JSON.stringify({state: 'complete', checks: 5, fetches,
    librechat_version: installed('./package.json').version,
    langchain_openai_version: installed('@langchain/openai/package.json').version,
    network_used: false, scope: 'installed_sdk_formatter_and_sse_parser_with_actual_adapter_fake_fetch'}) + '\n');
})().catch(error => { console.error(error); process.exitCode = 1; });
