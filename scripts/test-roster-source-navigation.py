import importlib.util,pathlib,tempfile,shutil,unittest
spec=importlib.util.spec_from_file_location('source',pathlib.Path(__file__).with_name('roster-source-navigation-operation.py'));m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
p=m.p
class SourceBoundary(unittest.TestCase):
 def test_exact_paths(self):
  for f in p.ALLOWED_FILES:p.validate({'method':p.METHODS[0],'file':f,'line':0,'character':0})
  for f in ('workflow_registry.rb','../workflow_registry.rb','/home/bhones/Downloads/AGENTS.md','Gemfile'):
   with self.subTest(file=f),self.assertRaises(p.Refused):p.validate({'method':p.METHODS[0],'file':f,'line':0,'character':0})
 def test_source_copies_match(self):
  for f in p.ALLOWED_FILES:self.assertEqual((p.FIXTURE/f).read_bytes(),(p.ROOT/'lib/soul_core'/f).read_bytes())
 def test_metadata_is_requested_file_and_private_copy_removed(self):
  original=p.Server;stages=[]
  class Fake:
   def __init__(self):stages.append(p.FIXTURE)
   def initialize(self):pass
   def query(self,q):return []
   def close(self):pass
  try:
   p.Server=Fake
   r=m.run(['symbols','workflow_handler_registry.rb','0','0'])
   self.assertEqual(r['data']['file'],'workflow_handler_registry.rb')
   self.assertEqual(r['data']['snapshot'],'soul-workflows-a1')
   self.assertTrue(stages);self.assertTrue(all(not s.exists() for s in stages))
  finally:p.Server=original
 def test_tampered_snapshot_refused(self):
  original=p.FIXTURE
  with tempfile.TemporaryDirectory() as tmp:
   try:
    dest=pathlib.Path(tmp)/'source';shutil.copytree(original,dest);p.FIXTURE=dest
    (dest/'workflow_handler_registry.rb').write_text('# changed')
    with self.assertRaises(p.Refused):m.run(['symbols','workflow_handler_registry.rb','0','0'])
   finally:p.FIXTURE=original
 def test_snapshot_symlink_refused(self):
  original=p.FIXTURE
  with tempfile.TemporaryDirectory() as tmp:
   try:
    dest=pathlib.Path(tmp)/'source';shutil.copytree(original,dest);p.FIXTURE=dest
    f=dest/'workflow_handler_registry.rb';f.unlink();f.symlink_to('/nonexistent')
    with self.assertRaises(p.Refused):m.run(['symbols','workflow_handler_registry.rb','0','0'])
   finally:p.FIXTURE=original
if __name__=='__main__':unittest.main()
