'use strict';
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=fs.readFileSync('assets/dashboard/dashboard.js','utf8');
const start=source.indexOf('    if (dataOf(envelope).code === "roster_busy"');
const end=source.indexOf('    if (!voiceRoundTrip',start);
assert(start>0&&end>start);
for(const [draft,active,proof,expected] of [['','chat',false,'retry text'],['new draft','chat',false,'new draft'],['','other',false,''],['','chat',true,'']]){
 const input={value:draft},messages=[],activity=[];
 const ctx=vm.createContext({input,state:{activeChat:{id:active}},chatId:'chat',message:'retry text',envelope:{lifecycle_state:'awaiting_input',data:{code:'roster_busy',request_admitted:proof,reason:'Wait for the current request to finish, then try again.'}},dataOf:x=>x.data,announce:x=>messages.push(x),setSoulActivity:(...x)=>activity.push(x)});
 vm.runInContext(source.slice(start,end),ctx);
 assert.equal(input.value,expected);
 if(!proof){assert.match(messages[0],/then try again/);assert.equal(activity[0][0],'awaiting_input');}
 else assert.equal(activity.length,0);
}
console.log('Busy notice: explicit proof, draft restoration, newer draft and chat selection preserved');
