# requires compiling native extensions with electron support
NPARAMS=--runtime=electron --target=7.1.11 --disturl=https://atom.io/download/electron
LINUX_VM=ncannasse@virtbuntu
PREBUILT_OSX_BINDINGS=https://gist.github.com/rcstuber/9f60840ccc371c8d53b18c6331b2bf7f/raw/4b5772d40fdae3c9c0f776ea53a43a71810db8b8/ffi_bindings_osx.tar.gz

all:

deps:
	npm install node-gyp -g
	npm install $(NPARAMS)
	(cd node_modules/deasync && rm -rf bin && node-gyp rebuild $(NPARAMS))	
	
cleanup:
	/bin/find . -name *.obj | xargs rm -f 
	/bin/find . -name *.pdb | xargs rm -f 
	/bin/find . -name *.tlog | xargs rm -rf 
	/bin/find . -name *.map | xargs rm -rf 

# git pull && sudo rm -rf node_modules && sudo make deps on LINUX_VM before running this
import_linux_bindings:
	cp bindings.js node_modules/bindings/	
	make LIB=ffi-napi NAME=ffi_bindings _import_linux_bindings
	make LIB=ref-napi NAME=binding _import_linux_bindings
	make LIB=deasync NAME=deasync _import_linux_bindings

_import_linux_bindings:
	-mkdir node_modules/$(LIB)/build/linux
	pscp $(LINUX_VM):hashlink-debugger/node_modules/$(LIB)/build/Release/$(NAME).node node_modules/$(LIB)/build/linux/
	chmod +x node_modules/$(LIB)/build/linux/$(NAME).node
	-cp bindings.js node_modules/$(LIB)/node_modules/bindings

bundle_mac_bindings:
	TMP=$$(mktemp -d); \
	cp 	node_modules/ffi-napi/build/Release/ffi_bindings.node \
		node_modules/ref-napi/build/Release/binding.node \
		node_modules/deasync/build/Release/deasync.node \
		$$TMP; \
	tar -cvzf ffi_bindings_osx.tar.gz -C $$TMP .; \
	rm -rf $$TMP;

import_mac_bindings:
	cp bindings.js node_modules/bindings/
	rm ffi_bindings_osx.tar.gz || true
	wget --no-check-certificate --content-disposition $(PREBUILT_OSX_BINDINGS)
	TMP=.tmp; mkdir -p $$TMP; \
	tar -C $$TMP -xf ffi_bindings_osx.tar.gz; \
	make SRC=$$TMP LIB=ffi-napi NAME=ffi_bindings _import_mac_bindings; \
	make SRC=$$TMP LIB=ref-napi NAME=binding _import_mac_bindings; \
	make SRC=$$TMP LIB=deasync NAME=deasync _import_mac_bindings; \
	rm -rf $$TMP; \
	rm ffi_bindings_osx.tar.gz;

_import_mac_bindings:
	-mkdir -p node_modules/$(LIB)/build/darwin
	chmod +x $(SRC)/$(NAME).node
	-cp $(SRC)/$(NAME).node node_modules/$(LIB)/build/darwin
	-cp bindings.js node_modules/$(LIB)/node_modules/bindings


package: cleanup
	#npm install vsce -g
	vsce package
	
# to get token : 
# - visit https://dev.azure.com/ncannasse/
# - login (@hotmail)
# - click user / security / Personal Access token
publish:
	vsce publish -p `cat vsce_token.txt`
