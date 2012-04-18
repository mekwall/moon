try {
	module.exports = require('./lib/moon');
} catch (e) {
	require('iced-coffee-script');
	module.exports = require('./src/moon');
}