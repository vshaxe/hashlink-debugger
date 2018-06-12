# requires compiling native extensions with electron support
NPARAMS=--runtime=electron --target=1.7.9 --disturl=https://atom.io/download/electron

deps:
	npm install node-gyp -g
	npm install $(NPARAMS)
	(cd node_modules/deasync && rm -rf bin && node-gyp rebuild $(NPARAMS))	
	
cleanup:
	/bin/find . -name *.obj | xargs rm -f 
	/bin/find . -name *.pdb | xargs rm -f 
	/bin/find . -name *.tlog | xargs rm -rf 
	/bin/find . -name *.map | xargs rm -rf 
	
package: cleanup
	#npm install vsce -g
	vsce package
	
publish:
	#npm install vsce -g
	vsce publish -p ${VSCE_TOKEN}