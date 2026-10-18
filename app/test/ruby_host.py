"""Isolated audit runner using the installed Ruby DLL; does not launch or edit SketchUp."""
import ctypes, os, pathlib, sys
base=pathlib.Path(r'C:\Program Files\SketchUp\SketchUp 2026\SketchUp')
os.add_dll_directory(str(base))
os.environ['RUBYLIB']=str(base/'Tools'/'RubyStdLib')+';'+str(base/'Tools'/'RubyStdLib'/'platform_specific')
os.environ['GEM_HOME']=str(base/'Tools'/'gems'/'3.2.0')
os.environ['GEM_PATH']=os.environ['GEM_HOME']
ruby=ctypes.PyDLL(str(base/'x64-ucrt-ruby320.dll'))
ruby.ruby_sysinit.argtypes=[ctypes.POINTER(ctypes.c_int),ctypes.POINTER(ctypes.POINTER(ctypes.c_char_p))]
args=[b'ruby',b'--disable-gems',*([os.fsencode(x) for x in sys.argv[1:]] or [b'-e',b'puts RUBY_DESCRIPTION; puts 2+3'])]
argc=ctypes.c_int(len(args))
argv_store=(ctypes.c_char_p*(len(args)+1))(*args,None)
argv=ctypes.cast(argv_store,ctypes.POINTER(ctypes.c_char_p))
ruby.ruby_sysinit(ctypes.byref(argc),ctypes.byref(argv))
ruby.ruby_init()
ruby.ruby_options.argtypes=[ctypes.c_int,ctypes.POINTER(ctypes.c_char_p)]
ruby.ruby_options.restype=ctypes.c_void_p
ruby.ruby_run_node.argtypes=[ctypes.c_void_p]
ruby.ruby_run_node.restype=ctypes.c_int
sys.exit(ruby.ruby_run_node(ruby.ruby_options(len(args),ctypes.cast(argv_store,ctypes.POINTER(ctypes.c_char_p)))))
