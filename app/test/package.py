from pathlib import Path
import json,zipfile,shutil,hashlib,time,sys
base=Path(__file__).resolve().parent.parent
development=base.parent
out=development.parent/'deliverables'
out.mkdir(exist_ok=True)
report=json.loads((base/'test'/'export_results.json').read_text())
latest=Path(report['export_folder'])
if '--source' in sys.argv:
    latest=Path(sys.argv[sys.argv.index('--source')+1])
if not latest.is_dir(): latest=base/'example_export'
example=base/'example_export'
if latest.resolve()!=example.resolve():
    # Preserve the prior example instead of deleting it. Validate both paths
    # before moving a directory, including when this script runs on Windows.
    workspace=development.parent.resolve()
    archive=workspace/'output'/('example_archive_'+str(time.time_ns()))
    for target in (latest.resolve(),example.resolve(),archive.resolve()):
        if not target.is_relative_to(workspace): raise ValueError('Path outside workspace')
    if example.exists():
        archive.parent.mkdir(exist_ok=True)
        example.rename(archive)
    shutil.copytree(latest,example)
status={'version':json.loads((example/'job.json').read_text())['version'],
        'offline_file_checks':'See aspire_reader_results.json and aspire_static_results.json',
        'ruby_extended_check':'blocked_by_automatic_approval_review_due_to_unexpected_external_telemetry',
        'live_sketchup':'not_verified','live_aspire':'not_verified',
        'reason':'Generated DXF file checks are separate from native application import. Test the Aspire R12 compatibility samples in a millimetre job.'}
(base/'test'/'live_status.json').write_text(json.dumps(status,indent=2))
# Keep reports portable inside the delivered development folder.
report['export_folder']='app/example_export'
report['dxf_revision']=status['version']
report['dxf_verification_reports']=['aspire_reader_results.json','aspire_static_results.json']
report['version_scope']='Original geometry/BOM/PDF audit version; DXF revision has separate reports.'
(base/'test'/'export_results.json').write_text(json.dumps(report,indent=2))
if '--stage-only' in sys.argv:
    print(json.dumps({'staged_example':str(example)}))
    raise SystemExit(0)
files=[p for p in development.rglob('*') if p.is_file() and not any(x in p.relative_to(development).parts for x in ('test_output','live_test','pdf_previews','__pycache__'))]
zip_path=out/'AJ_Board_Kitchen_Ruby_Test.zip'
with zipfile.ZipFile(zip_path,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
    for p in sorted(files):z.write(p,Path(development.name)/p.relative_to(development))
for name in ['BOM.pdf','Part_Stickers.pdf']:
    shutil.copyfile(example/name,out/('AJ_'+name))
print(json.dumps({'zip':str(zip_path),'size':zip_path.stat().st_size,'sha256':hashlib.sha256(zip_path.read_bytes()).hexdigest(),'files':len(files)}))
