#!/usr/bin/env node

var program = require('commander')
  , spawn = require('child_process').spawn
  , resolve = require('path').resolve
  , fs = require('fs');

program
  .version(JSON.parse(fs.readFileSync(__dirname + '/../package.json', 'utf8')).version)
  .usage('[options]')
  .option('-r, --reporter <reporter>', 'Mocha reporter', 'spec')
  .option('-w, --watch', 'Watch for file changes and retest')
  .option('-l, --location <URL>', 'Base URL to use for tests', 'http://localhost')
  .option('-d, --debug', 'Output selenium debug info')
  .option('-h, --headless', 'Request a headless browser')
  .option('-f, --file <dir|file>', 'Location of test(s) to run', './tests')
  .option('-s, --selenium <URL>', 'URL of the selenium server to use', 'localhost')
  .option('-i, --repeat <n>', 'Repeat tests', parseInt, 1)
  .option('-p, --processes <n>', 'Concurrent processes to use for tests', parseInt, 1)
  .option('-S, --stagger <n>', 'Stagger tests', parseInt, 0)
  .option('-t, --timeout <n>', 'Time limit for each test', parseInt, 300000)
  .option('-d, --data <file>', 'JSON data file to use for tests')
  .option('-I, --index <n>', 'Server index number (multiple test runners)', parseInt, 1)
  .option('-o, --offset <n>', 'Number of data records to skip', parseInt, 0)
  .option('-T, --tags', 'Show tag information for tests')
  .option('-b, --browser <name>', 'Name of browser to test against')
  .option('-O, --os <OS>', 'Operating system to test against')
  .option('-v, --browserversion <version>', 'Browser version to test against')
  .option('-x, --raw', 'Raw output')
  .parse(process.argv);

program.name = 'swd';

var cmd = (program.repeat > 1 || program.processes > 1) ? 'parallel-mocha' : 'mocha';

var args = [
  '--compilers', 'coffee:coffee-script/register',
  '--reporter', program.reporter,
  '--repeat', program.repeat,
  '--require', 'should',
  '--timeout', program.timeout,
  '--slow', 30000,
  '--processes', program.processes,
  '--stagger', program.stagger,
  '--offset', program.offset
];

if (program.watch) {
  args.push('--growl');
  args.push('--watch');
}

if ((program.repeat > 1 || program.processes > 1) && program.raw) {
  args.push('--raw');
}

if (program.repeat > 1) {
  args.push('--index');
  args.push(program.index);

  if (program.data) {
    args.push('--data');
    args.push(program.data);
  }
}

args.push(program.file);

var env = process.env;

env.NODE_ENV = "test";
env.APP_HOME = process.cwd();
env.LOCATION = program.location;
env.DEBUG = (program.debug) ? 1 : 0;
env.HEADLESS = (program.headless) ? 1 : 0;
env.SELENIUM = program.selenium;
env.SHOW_TAGS = (program.tags) ? 1 : 0;
env.REPORTER = program.reporter;

if (program.browser) {
  env.BROWSER = program.browser;
}

if (program.browserversion) {
  env.BROWSER_VERSION = program.browserversion;
}

if (program.os) {
  env.PLATFORM = program.os;
}

var opts = {
  env : env,
  "customFds": [0,1,2]
}

var proc = spawn(cmd, args, opts);
proc.on('exit', function (code, signal) {
  process.on('exit', function(){
    if (signal) {
      process.kill(process.pid, signal);
    } else {
      process.exit(code);
    }
  });
});
