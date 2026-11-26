switch(process.platform) {
	case "win32":
		module.exports = require('./lib/win/hldebug.node');
		break;
	case "darwin":
		module.exports = require('./lib/mac/hldebug.node');
		break;
	case "linux":
		module.exports = require('./lib/linux/hldebug.node');
		break;
}
