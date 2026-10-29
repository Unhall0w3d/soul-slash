'use strict';
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=fs.readFileSync('assets/dashboard/dashboard.js','utf8');
const nodes=new Map(),sent=[],notices=[];
function byId(id){if(!nodes.has(id))nodes.set(id,{value:'',textContent:'',listeners:{},addEventListener(type,fn){this.listeners[type]=fn;},requestSubmit(){sent.push(byId('message-input').value);byId('message-input').value='';}});return nodes.get(id);}
let state={activeChat:{roster_member:'gemma-4-e4b-cpu'},busy:false,rosterRequest:null};
const ctx=vm.createContext({byId,state,announce:x=>notices.push(x),dataOf:x=>x.data,callSoul:async op=>{assert.equal(op,'cpu.status');return {lifecycle_state:'complete',data:{cpu_only:true,state:'loaded'}};}});
vm.runInContext(source.slice(source.indexOf('// Explicit clicks submit user commands')),ctx);
const click=id=>byId(id).listeners.click();
byId('cpu-task-id').value='t-'+'a'.repeat(24);byId('cpu-task-digest').value='b'.repeat(64);
click('cpu-task-preview');assert.equal(byId('cpu-task-digest').value,'');assert.match(sent.pop(),/^\/task preview /);
click('cpu-task-run');assert.equal(sent.length,0);assert.match(notices.pop(),/Review a fresh preview/);
byId('cpu-task-digest').value='b'.repeat(64);click('cpu-task-run');assert.deepEqual(JSON.parse(sent.pop().slice(10)),{task_id:'t-'+'a'.repeat(24),expected_digest:'b'.repeat(64)});
state.busy=true;click('cpu-task-run');assert.equal(sent.length,0);state.busy=false;
byId('message-input').value='User draft';click('cpu-task-run');assert.equal(sent.length,0);assert.equal(byId('message-input').value,'User draft');byId('message-input').value='';
state.activeChat.roster_member='gpt-oss-20b';click('cpu-task-run');assert.equal(sent.length,0);
(async()=>{await click('cpu-member-refresh');assert.match(byId('cpu-member-status').textContent,/resident in system RAM/);console.log('CPU UI: explicit preview/run, exact digest, busy/draft/member boundaries and separate residency passed');})().catch(e=>{console.error(e);process.exitCode=1;});
