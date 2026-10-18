"""Build the empty R2000 document used by the dependency-free Ruby exporter."""
from pathlib import Path
from io import StringIO
import json
import ezdxf

base = Path(__file__).resolve().parent.parent
doc = ezdxf.new('R2000')
doc.units = 4
doc.header['$MEASUREMENT'] = 1
doc.header['$LUNITS'] = 2
doc.header['$LUPREC'] = 4
doc.header['$INSBASE'] = (0, 0, 0)
stream = StringIO()
doc.write(stream)
lines = stream.getvalue().splitlines()
tags = [[int(lines[i]), lines[i + 1].strip()] for i in range(0, len(lines), 2)]
template = {
    'format': 'AC1015',
    'generator': 'ezdxf ' + ezdxf.__version__,
    'modelspace_owner': doc.modelspace().block_record_handle,
    'layer_table_handle': doc.layers.head.dxf.handle,
    'tags': tags,
}
path = base / 'vendor' / 'dxf_r2000_template.json'
path.write_text(json.dumps(template, separators=(',', ':')), encoding='utf-8')
print(path)
