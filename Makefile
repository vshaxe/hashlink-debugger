all:

deps:
	npm install
cleanup:
	/bin/find . -name *.obj | xargs rm -f 
	/bin/find . -name *.pdb | xargs rm -f 
	/bin/find . -name *.tlog | xargs rm -rf 
	/bin/find . -name *.map | xargs rm -rf 
package: cleanup
	#npm install -g @vscode/vsce
	haxe -cp src -lib vscode -lib vshaxe -D js-es=6 -js extension.js Extension
	vsce package
	
# to get token : 
# - visit https://dev.azure.com/ncannasse/
# - login (@hotmail)
# - click user / security / Personal Access token
# - select Organization:All + Full Access
publish:
	vsce publish -p `cat vsce_token.txt`
