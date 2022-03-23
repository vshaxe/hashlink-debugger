switch(process.platform) {
	case "win32":
		module.exports = require('hldebug/lib/win/hldebug.node');
		break;
	case "darwin":
		module.exports = require('hldebug/lib/mac/hldebug.node');
		break;
	case "linux":
		module.exports = require('hldebug/lib/linux/hldebug.node');
		break;
}
