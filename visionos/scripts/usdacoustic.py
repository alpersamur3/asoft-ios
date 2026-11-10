"""Synthetic rooms without their audio inputs (guard while the guest has no audio: backboardd aborts with 'Cannot
create a PHASEMaterial with nil or invalid PHASEEngine'). Removes the root prims that only feed PHASE: the simulated
scene-reconstruction mesh (SceneUnderstanding_PRR_Mesh, per-part acoustic materials such as MaterialFabric) and the
room acoustics (AcousticScenes, rt60). The visual model, the planes and the IBL stay.
    usdacoustic.py list ROOM.usdc
    usdacoustic.py strip ROOM.usdc OUT.usdc
Run with a Python that has usd-core (the rooms step makes a venv with usd-core 26.11 for it).
"""
import sys
from pxr import Sdf, Usd

DROP = ('SceneUnderstanding_PRR', 'AcousticScene')

cmd, src = sys.argv[1], sys.argv[2]
if cmd == 'list':
    st = Usd.Stage.Open(src)
    for p in st.GetPseudoRoot().GetChildren():
        print(p.GetPath(), p.GetTypeName(), len(list(Usd.PrimRange(p))), 'prims')
else:
    out = sys.argv[3]
    layer = Sdf.Layer.FindOrOpen(src)
    st0 = Usd.Stage.Open(src)
    before = {r.name: len(list(Usd.PrimRange(st0.GetPrimAtPath(r.path)))) for r in layer.rootPrims}
    gone = [r.name for r in layer.rootPrims if r.name.startswith(DROP)]
    for name in gone:
        del layer.rootPrims[name]
    # Acoustic material tags left on the visual meshes and planes go too (classification stays).
    tagged = []
    def untag(path):
        spec = layer.GetPrimAtPath(path) if path.IsPrimPath() else None
        if spec and 'preliminary:sceneUnderstanding:material' in spec.properties:
            spec.RemoveProperty(spec.properties['preliminary:sceneUnderstanding:material'])
            tagged.append(str(path))
    layer.Traverse(Sdf.Path.absoluteRootPath, untag)
    print('material tags removed', len(tagged), tagged[:4])
    layer.Export(out)
    st = Usd.Stage.Open(out)
    after = {p.GetName(): len(list(Usd.PrimRange(p))) for p in st.GetPseudoRoot().GetChildren()}
    kept_same = all(before[k] == v for k, v in after.items())
    print('removed', gone, 'kept', after, 'unchanged' if kept_same else 'CHANGED', 'default', st.GetDefaultPrim().GetPath())
