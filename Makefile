# requires compiling native extensions with electron support
NPARAMS=--runtime=electron --target=2.0.5 --disturl=https://atom.io/download/electron

deps:
	npm install node-gyp -g
	npm install $(NPARAMS)
	(cd node_modules/deasync && rm -rf bin && node-gyp rebuild $(NPARAMS))	
	
cleanup:
	/bin/find . -name *.obj | xargs rm -f 
	/bin/find . -name *.pdb | xargs rm -f 
	/bin/find . -name *.tlog | xargs rm -rf 
	/bin/find . -name *.map | xargs rm -rf 

import_linux_bindings:
	cp bindings.js node_modules/bindings/	
	make LIB=ffi NAME=ffi_bindings _import_linux_bindings
	make LIB=ref NAME=binding _import_linux_bindings
	make LIB=deasync NAME=deasync _import_linux_bindings

_import_linux_bindings:
	-mkdir node_modules/$(LIB)/build/linux
	pscp ncannasse@virtbuntu:hashlink-debugger/node_modules/$(LIB)/build/Release/$(NAME).node node_modules/$(LIB)/build/linux/
	chmod +x node_modules/$(LIB)/build/linux/$(NAME).node
	-cp bindings.js node_modules/$(LIB)/node_modules/bindings	
	
package: cleanup
	#npm install vsce -g
	vsce package
	
publish:
	vsce publish -p `cat vsce_token.txt`