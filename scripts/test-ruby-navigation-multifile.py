#!/usr/bin/env python3
import importlib.util,pathlib,tempfile,json,unittest
spec=importlib.util.spec_from_file_location('multi',pathlib.Path(__file__).with_name('pilot-ruby-navigation-multifile.py'));m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
p=m.p
class MultiFile(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.d=pathlib.Path(self.tmp.name)/'receipts';self.q={'method':p.METHODS[0],'file':'calls.rb','line':3,'character':35}
 def tearDown(self):self.tmp.cleanup()
 def test_exact_file_allowlist(self):
  for f in p.ALLOWED_FILES:p.validate(dict(self.q,file=f))
  for f in ('extra.rb','../alpha.rb','/fixture/alpha.rb','Gemfile','dependencies.json','/home/bhones/Downloads/agents.md'):
   with self.subTest(file=f),self.assertRaises(p.Refused):p.validate(dict(self.q,file=f))
 def test_return_allowlist(self):
  for f in p.ALLOWED_FILES:p.check_result({'uri':'file:///fixture/'+f})
  with self.assertRaises(p.Refused):p.check_result({'targetUri':'file:///fixture/extra.rb'})
 def test_source_file_in_replay_binding(self):
  p.invoke(self.d,p.MEMBERS[0],'r1',self.q,'pin',lambda _:[])
  with self.assertRaises(p.Refused):p.invoke(self.d,p.MEMBERS[0],'r1',dict(self.q,file='alpha.rb'),'pin',lambda _:[])
 def test_reference_label_and_exact_replay(self):
  q=dict(self.q,method=p.METHODS[1]);r=p.invoke(self.d,p.MEMBERS[0],'r1',q,'pin',lambda _:[])
  replay=p.invoke(self.d,p.MEMBERS[0],'r1',q,'pin',lambda _:self.fail('executed again'))
  self.assertEqual(r['result_label'],'possible references');self.assertEqual(replay['result_label'],r['result_label'])
 def test_cross_file_scoring_preserves_filename(self):
  def loc(f):return {'uri':'file:///fixture/'+f,'range':{'start':{'line':3,'character':4}}}
  self.assertEqual(m.normalize_locations([loc('alpha.rb'),loc('beta.rb'),loc('alpha.rb')]),[('alpha.rb',3),('beta.rb',3)])
 def test_nested_symbols_scoring(self):
  x=[{'name':'A','kind':2,'selectionRange':{'start':{'line':1}},'children':[{'name':'B','kind':5,'selectionRange':{'start':{'line':2}}}]}]
  self.assertEqual(m.symbols(x),[['A',2,1],['A::B',5,2]])
 def test_reviewed_snapshot_valid(self):self.assertTrue(m.verify_snapshot())
 def test_modified_snapshot_refused(self):
  original=p.FIXTURE
  try:
   p.FIXTURE=pathlib.Path(self.tmp.name)/'snapshot';p.FIXTURE.mkdir();(p.FIXTURE/'snapshot.json').write_text('{}');(p.FIXTURE/'extra.rb').write_text('# extra')
   with self.assertRaises(p.Refused):m.verify_snapshot()
  finally:p.FIXTURE=original
 def test_symlink_member_refused(self):
  original=p.FIXTURE
  try:
   p.FIXTURE=pathlib.Path(self.tmp.name)/'snapshot';p.FIXTURE.mkdir();(p.FIXTURE/'calls.rb').symlink_to('/nonexistent')
   with self.assertRaises(p.Refused):p.validate(self.q)
  finally:p.FIXTURE=original
if __name__=='__main__':unittest.main()
