all:

deps:
	cd hldebug-wrapper && npm install && rm -rf build node_modules
	npm install
cleanup:
	/bin/find . -name *.obj | xargs rm -f 
	/bin/find . -name *.pdb | xargs rm -f 
	/bin/find . -name *.tlog | xargs rm -rf 
	/bin/find . -name *.map | xargs rm -rf 
build:
	haxe -cp src -lib vscode -lib vshaxe -lib vscode-debugadapter -lib format -lib hscript -D js-es=6 -js extension.js Extension
package: cleanup build
	#npm install vsce -g
	vsce package
	
# to get token : 
# - visit https://dev.azure.com/ncannasse/
# - login (@hotmail)
# - click user / security / Personal Access token
# - select Organization:All + Full Access
publish:
	vsce publish -p `cat vsce_token.txt`
