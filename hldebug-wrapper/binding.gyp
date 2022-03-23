{
  'targets': [
    {
      'target_name': 'hldebug',
      'sources': [ 'src/debug.c', 'src/hldebugger.cc' ],
      'include_dirs': ["<!@(node -p \"require('node-addon-api').include\")", 'src/' ],
      'conditions': [
        [ "OS=='mac'", { 
          "sources": [ 'src/mdbg/mdbg.c', 'src/mdbg/mach_excServer.c', 'src/mdbg/mach_excUser.c' ]
	}]
      ],
      'dependencies': ["<!(node -p \"require('node-addon-api').gyp\")"],
      'defines': [ 'LIBHL_STATIC' ],
      'cflags!': [ '-fno-exceptions' ],
      'cflags_cc!': [ '-fno-exceptions' ],
      'xcode_settings': {
        'GCC_ENABLE_CPP_EXCEPTIONS': 'YES',
        'CLANG_CXX_LIBRARY': 'libc++',
        'MACOSX_DEPLOYMENT_TARGET': '10.7'
      },
      'msvs_settings': {
        'VCCLCompilerTool': { 'ExceptionHandling': 1 },
      }
    },
    {
      "target_name": "copy_binary",
      "type": "none",
      "dependencies": [ "hldebug" ],
      "copies": [
        {
          "files": [ "<(PRODUCT_DIR)/hldebug.node" ],
          "destination": "./lib/<(OS)"
        }
      ]
    }
  ]
}
