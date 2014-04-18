require('package-script').spawn([
  {
    command: "npm",
    args: ["install", "-g", "mocha"]
  },
  {
    command: "npm",
    args: ["install", "-g", "git+ssh://git@github.com:beachmint/parallel-mocha.git#v0.2.22"]
  },
  {
    command: "npm",
    args: ["install", "-g", "should"]
  },
  {
    command: "npm",
    args: ["install", "-g", "selenium-ui-mocha-reporter"]
  } 
]);
