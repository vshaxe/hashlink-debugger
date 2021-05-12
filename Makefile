# requires compiling native extensions with electron support
NPARAMS=--runtime=electron --target=12.0.4 --disturl=https://atom.io/download/electron
LINUX_VM=ncannasse@virtbuntu
PREBUILT_OSX_BINDINGS=https://gist.github.com/rcstuber/3e9a46fa0aae9f729648445a0a9717d7/raw/221e37bcbf22c2cae216aa664ee960e8413899f5/ffi_bindings_osx.tar.gz

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
	make LIB=deasync NAME=deasync _import_linux_bindings

_import_linux_bindings:
	-mkdir node_modules/$(LIB)/build/linux
	pscp $(LINUX_VM):hashlink-debugger/node_modules/$(LIB)/build/Release/$(NAME).node node_modules/$(LIB)/build/linux/
	chmod +x node_modules/$(LIB)/build/linux/$(NAME).node
	-cp bindings.js node_modules/$(LIB)/node_modules/bindings

bundle_mac_bindings:
	TMP=$$(mktemp -d); \
	cp 	node_modules/deasync/build/Release/deasync.node \
		$$TMP; \
	tar -cvzf ffi_bindings_osx.tar.gz -C $$TMP .; \
	rm -rf $$TMP;

import_mac_bindings:
	cp bindings.js node_modules/bindings/
	rm ffi_bindings_osx.tar.gz || true
	wget --no-check-certificate --content-disposition $(PREBUILT_OSX_BINDINGS)
	TMP=.tmp; mkdir -p $$TMP; \
	tar -C $$TMP -xf ffi_bindings_osx.tar.gz; \
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
