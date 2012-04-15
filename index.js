try {
	module.exports = require('./lib/moon');
} catch (e) {
	require('coffee-script');
	module.exports = require('./src/moon');
}