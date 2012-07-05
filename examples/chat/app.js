/**
* Moon.js Chat Example
*/
//
try {
  var agent = require("webkit-devtools-agent");
} catch (e) {}
// A wrapper for our coffee-script app
try {
  // If installed through npm
  var Application = require("moon");
} catch (e) {
  // If checked out from git
  var Application = require("../../index");
}
var app = new Application();
app = require("./app.coffee")(app);