// A wrapper for our coffee-script app
var app = new ( require("../../index") )();
app = require("./app.coffee")(app);