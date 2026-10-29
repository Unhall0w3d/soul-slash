"""Prepare an isolated synthetic editor review from the user-saved native template."""
import copy, hashlib, json, os, shutil, tempfile, time, uuid
from pathlib import Path
import xml.etree.ElementTree as ET
BASE = Path(__file__).resolve().parents[1] / 'Soul/runtime/qualification/video-editing-a1-20261028-2-u9rv2h'
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def put(e, key, value):
    node=e.find(f"property[@name='{key}']")
    if node is None: node=ET.SubElement(e,'property',name=key)
    node.text=str(value)
def prop(e,key):
    node=e.find(f"property[@name='{key}']")
    return node.text if node is not None else None
def build(native, pilot, destination, profile_path):
    profile_path=Path(profile_path)
    assert profile_path.is_file() and not profile_path.is_symlink()
    settings=dict(line.split('=',1) for line in profile_path.read_text().splitlines() if '=' in line)
    assert all(settings.get(k)==v for k,v in pilot.find('profile').attrib.items()), 'editor profile differs from render profile'
    root=copy.deepcopy(native)
    root.set('root',str(destination))
    profile=root.find('profile');profile.attrib.update(pilot.find('profile').attrib)
    seq=next(t for t in root.findall('tractor') if prop(t,'kdenlive:uuid'))
    old_id=seq.get('id');new_id='{'+str(uuid.uuid4())+'}'
    seq.set('id',new_id);seq.set('in','0');seq.set('out','239')
    for node in root.iter():
        if node.get('producer')==old_id: node.set('producer',new_id)
        if node.tag=='property' and node.text==old_id:node.text=new_id
    for k,v in {'kdenlive:clipname':'Soul eight-second edit','kdenlive:duration':'00:00:08.000','kdenlive:maxduration':240,'kdenlive:zone_in':0,'kdenlive:zone_out':240,'kdenlive:sequenceproperties.position':0,'kdenlive:sequenceproperties.zonein':0,'kdenlive:sequenceproperties.zoneout':240,'kdenlive:sequenceproperties.audioTarget':0}.items():put(seq,k,v)
    black=root.find('producer');black.set('in','0');black.set('out','239')
    source=pilot.find("chain[@id='source']")
    control='{'+str(uuid.uuid4())+'}'
    chains=[]
    for name in ['source','audio','clip0','clip1']:
        original=pilot.find(f"chain[@id='{name}']") if name.startswith('clip') else source
        node=copy.deepcopy(original);node.set('id','review_'+name)
        # Captioned assets need distinct bin identities: Kdenlive coalesces
        # producers with the same bin identity when saving the project.
        captioned=name.startswith('clip')
        put(node,'kdenlive:id',5+int(name[-1]) if captioned else 4)
        put(node,'kdenlive:control_uuid','{'+str(uuid.uuid4())+'}' if captioned else control)
        if captioned:put(node,'kdenlive:clipname',f'Captioned cut {int(name[-1])+1}')
        if name=='audio':put(node,'set.test_image',1);put(node,'video_index',-1)
        if name.startswith('clip'):put(node,'set.test_audio',1);put(node,'audio_index',-1)
        chains.append(node)
    for i,node in enumerate(chains):root.insert(2+i,node)
    for playlist, names in [('playlist0',['review_audio']*2),('playlist4',['review_clip0','review_clip1'])]:
        target=root.find(f"playlist[@id='{playlist}']")
        assert target is not None and not target.findall('entry')
        for producer,(start,end) in zip(names,[(30,149),(210,329)]):
            ET.SubElement(target,'entry',producer=producer,attrib={'in':str(start),'out':str(end)})
    bin=root.find("playlist[@id='main_bin']")
    put(bin,'kdenlive:docproperties.documentid',int(time.time()*1000))
    put(bin,'kdenlive:docproperties.profile',profile_path.resolve())
    # Keep the native mixer layout; mono source/export does not require a mono
    # editor mixer. Switching its channel count triggers the 26.08.2 meter crash.
    assert prop(bin,'kdenlive:docproperties.audioChannels')=='2'
    entry=bin.find('entry');entry.set('in','0');entry.set('out','239')
    ET.SubElement(bin,'entry',producer='review_source',attrib={'in':'0','out':'359'})
    for name in ['review_clip0','review_clip1']:
        ET.SubElement(bin,'entry',producer=name,attrib={'in':'0','out':'359'})
    wrapper=root.findall('tractor')[-1];wrapper.set('in','0');wrapper.set('out','239')
    track=wrapper.find('track');track.set('in','0');track.set('out','239')
    assert prop(bin,'kdenlive:docproperties.activetimeline')==new_id
    assert prop(seq,'kdenlive:control_uuid')==new_id and prop(seq,'kdenlive:producer_type')=='17'
    assert len(seq.findall('track'))==5 and prop(bin,'xml_retain')=='1'
    assert profile.get('frame_rate_num')=='30' and profile.get('width')=='640'
    return root
if __name__=='__main__':
    os.umask(0o077)
    receipt=json.loads((BASE/'receipt.json').read_text())
    for name,digest in receipt['outputs'].items():assert sha(BASE/name)==digest
    manifest=json.loads((BASE/'manifest.json').read_text())
    for name in ['original.mkv','original-backup.mkv']:assert sha(BASE/name)==manifest['source_sha256']
    source_hashes={n:sha(BASE/n) for n in ['editor-native-reference.kdenlive','pilot.kdenlive','original.mkv','original-backup.mkv']}
    root=Path(tempfile.mkdtemp(prefix='video-native-review-',dir=BASE.parent))
    for n in ['original.mkv','original-backup.mkv','reference.mkv','plan.json','manifest.json']:shutil.copy2(BASE/n,root/n)
    for n in ['original.mkv','original-backup.mkv']: (root/n).chmod(0o444)
    for n in ['config','cache','mlt-plugins']:(root/n).mkdir(mode=0o700)
    for n in (BASE/'mlt-plugins').iterdir(): (root/'mlt-plugins'/n.name).symlink_to(n.resolve(strict=True))
    native=ET.parse(BASE/'editor-native-reference.kdenlive').getroot();pilot=ET.parse(BASE/'timeline-review-v3.kdenlive').getroot()
    result=build(native,pilot,root,Path.home()/'.local/share/kdenlive/profiles/soul-pilot-360p30-709-20261028')
    with (root/'pilot.kdenlive').open('xb') as f:ET.ElementTree(result).write(f,encoding='utf-8',xml_declaration=True)
    assert all(sha(BASE/n)==h for n,h in source_hashes.items())
    (root/'preparation.json').write_text(json.dumps({'state':'prepared','source_hashes':source_hashes,'project_sha256':sha(root/'pilot.kdenlive'),'originals_unchanged':True},indent=2))
    print(root)
