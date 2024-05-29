# HashLink Debugger

This VSCode extension allows you to debug [HashLink](https://hashlink.haxe.org/) JIT applications.

*Only available on VSCode 64 bit*

## Building from Source

The following instructions are only relevant for building the extension from source and are **not required when installing it from the marketplace**.

### Compiling

You will need [Haxe 4](https://haxe.org/download/).

Additionally, you need to install these dependencies:

```
haxelib install vshaxe
haxelib install vscode
haxelib install vscode-debugadapter
haxelib install hscript
haxelib install format
```

You will need [NodeJS](https://nodejs.org/en/download), if you would like to compile vscode extension or use commandline nodejs version.

Additionally, you need to install dependencies:

```
npm install
```

Once all dependencies are ready, you should be able to compile with `make build`.

#### Commandline version

Instead of the vscode plugin, you can also compile and run a commandline version, similar to `gdb`:

Debugger running in HashLink;
```
cd hashlink-debugger/debugger
haxe debugger.hxml
hl debug.hl /my/path/filetodebug.hl
```

You can then use gdb-like commands such as run/bt/break/etc. (see [sources](https://github.com/vshaxe/hashlink-debugger/blob/master/hld/Main.hx#L219))

The commandline debugger can also be compiled and run using nodejs, by doing:
```
cd hashlink-debugger/debugger
haxe node_debug.hxml
npm install
node debugger.js /my/path/filetodebug.hl
```


### Installing

Please note that VSCode does not allow users to have a specific directory for a single extension, so it's easier to clone this repository directly into the `extensions` directory of VSCode (`C:\Users\<you>\.vscode\extensions` on Windows).

Alternatively, you can run `make package` (requires dependency `npm install vsce -g`) to generate VSCode extension package file (.vsix). It can be used with VSCode > Extensions > Install from VSIX.

### Supported Platforms

Supports Windows, Linux and Mac (Intel chip only, does not work with Rosetta). For OSX/MacOS make sure your Hashlink version is `1.12.0` or higher and you ran `make codesign_osx` during installation.
