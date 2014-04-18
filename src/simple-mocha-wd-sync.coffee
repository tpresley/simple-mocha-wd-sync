wd = require 'wd-sync'
colors = require 'colors'
_ = require 'underscore'

console.log "Base Test URL: ".blue + process.env.LOCATION.green if process.env.REPORTER isnt 'JSON-Stream' and process.env.REPORTER.indexOf('selenium-ui-mocha-reporter') is -1

module.exports = (helpers) ->

  # var for the selenium browser object
  browser = null

  # factory function that creates a wrapper to:
  #   1) enable the Fibers async framework to work
  #   2) automatically set the 'this' context of the test functions to the command/browser object for convenience
  wrapper = wd.wrap
    with: -> commands

  # get references to the mocha BDD functions so we can augment them
  real_describe = global.describe
  real_describe_only = global.describe.only
  real_describe_skip = global.describe.skip
  real_it = global.it
  real_it_only = global.it.only
  real_it_skip = global.it.skip

  # capture calls to the BDD "describe" function and augment with test boilerplate/setup steps
  global.describe = (name, args...) ->
   
    # if there are 2 arguments after the name, then the first is the list of helpers
    cb = if args.length is 1 then args[0] else args[1]
    helpers = args[0] if args.length is 2

    testCount = 1

    # call the original "describe" function and add in boilerplate "beforeEach" and "afterEach" methods
    real_describe.call this, name, =>
      extendedTestName = ''

      # called before each test ("it" function) is run
      beforeEach (done) ->
        testName = this.currentTest?.title ? ''
        extendedTestName = "#{name}: #{testCount} #{testName}"

        process.send({name: extendedTestName, status: 'starting'}) if process.send

        # auto-initialize the test
        newTest extendedTestName, helpers

        testCount++
        done()

      # called after each test ("it" function) is run
      afterEach (done) ->
        currentTest = @currentTest
        return (wrapper ->
          # auto quit the test and close the browser
          try
            @tag 'end'
            @printTags()
            try
              @sauceJobStatus(if currentTest.state is 'passed' then true else false)
            catch e2
              # nothing
            @quit() unless @dontQuit
            process.send({name: extendedTestName, status: currentTest.state}) if process.send
          catch e
            process.send({name: extendedTestName, status: 'error', message: e.message}) if process.send
          setTimeout done, 1000
        )()

      after (done) ->
        setTimeout done, 1000

      # re-attach the test
      cb.apply this

  # reattach the "describe" sub methods (only, skip)
  global.describe.only = (name, cb) ->
    real_describe_only.call this, name, cb

  global.describe.skip = (name, cb) ->
    real_describe_skip.call this, name, cb

  # capture calls to the BDD "it" function and inject the wrapper
  global.it = (name, cb) ->
    that = this
    real_it.call that, name, wrapper.call(that, cb)

  # reattach the "it" sub methods (only, skip)
  global.it.only = (name, cb) ->
    real_it_only.call this, name, cb

  global.it.skip = (name, cb) ->
    real_it_skip.call this, name, cb

  # friendly names for time durations
  global.normal = global.default = 1000
  global.short = 500
  global.long = 2000
  global.extralong = 4000
  global.superlong = 6000

 
  # commands is an augmented version of the selenium browser object
  # it is jQuery-like and allows you to query css sekector strings
  # using @('.my-class') syntax, and also makes the errors more friendly
  commands = (selector, maxWait=global.default, root=null) ->
    unless root
      root = this if this.elementById and not this.waitForElementById

    unless root
      try
        browser.waitForElementByCssSelector selector, maxWait
      catch e
        throw new Error "Unable to find element within #{maxWait}ms: #{selector}"

    try
      element = (root or browser).elementByCssSelector selector
      element.find = commands
      return element
    catch e
      throw new Error "Error getting element reference: #{selector}"

  # expose base url to tests for convenience
  commands.baseUrl = process.env.LOCATION

  # convenience method to search by XPaths
  commands.x = (xpath, maxWait, root=null) ->
    # if no explicit root element was passed in, attempt to use 'this' as the root (if it's an element)
    unless root
      root = this if this.elementById and not this.waitForElementById #quick and dirty check for if 'this' is an element object

    # if there's no root object to search from (searching from the top of DOM), then be nice and give the requested element some time to appear
    # - there isn't currently a selenium function to wait for an element when searching from a specified root element (maybe write one?)
    unless root
      try
        browser.waitForElementByXPath xpath, maxWait
      catch e
        throw new Error "Unable to find element within #{maxWait}ms: #{xpath}"

    try
      element = (root or browser).elementByXPath xpath
      element.find = commands
      return element
    catch e
      throw new Error "Error getting element reference: #{xpath}"

  # attach any data passed in from the command line
  if process.env.DATA
    try
      commands.data = JSON.parse process.env.DATA
    catch e
      commands.data = process.env.DATA


  #non-blocking sleep funcion
  commands.sleep = (ms=global.default) ->
    wd.sleep(ms)

 
  # function to register a new test, set up a new selenium session, and attach any helper methods needed
  newTest = (name, helpers, options={}) ->
    defaultOptions = 
      name: name
      browserName: process.env.BROWSER ? 'chrome'

    defaultOptions.platform = process.env.PLATFORM if process.env.PLATFORM
    defaultOptions.version = process.env.BROWSER_VERSION if process.env.BROWSER_VERSION

    testEnvironmentOptions = _.extend(defaultOptions, options)

    if ~~process.env.HEADLESS
      {browser} = wd.headless()
    else
      {browser} = wd.remote process.env.SELENIUM

    commands.browser = browser

    extendedTestName = name

    commands.start = (url) ->
      initTags()
      testInit = _.extend({}, testEnvironmentOptions)
      browser.init testInit
      browser.get url or process.env.LOCATION
      process.send({name: extendedTestName, status: 'started'}) if process.send


    # initialize time tagging vars/helpers
    tags = null
    previousTag = null
    initTags = -> 
      previousTag = 'start'
      tags = {start: new Date(), total: 0}

    # helper to calc amount of time to named points in the tests
    commands.tag = (name) ->
      # init the tags var if it hasn't been already
      if tags is null then initTags()
      # console.error('TAG: ' + previousTag + ' -> ' + name)
      previousTime = tags['total']
      tags['total'] = ~~((new Date() - tags.start) / 1000)
      tags[name] = tags['total'] - previousTime
      previousTag = name

    commands.getTags = ->
      return tags

    commands.printTags = ->
      return unless ~~process.env.SHOW_TAGS
      out = ''
      for tag, time of tags when tag isnt 'start'
        out += " #{tag}: #{time} "
      console.error 'TAGS: ' + out

    try
      globalActions = require(process.env.APP_HOME + '/helpers/global')
    catch e
      globalActions = null

    # Attach macros / helper functions
    # - attach the global library (lib/actions.coffee) first, to allow local overrides
    # - attach passed in helper files second (test/browser/xxx.coffee)
    # - finally attach methods from the browser object (can't overload base browser methods)

    if globalActions
      for name, fnc of globalActions when typeof fnc is 'function'
        do (name, fnc) ->
          commands[name] = (args...) ->
            try
              fnc.apply commands, args
            catch e
              argList = args.join(' ')
              throw new Error "Unable to #{name}: #{argList}"

    if helpers
      helpers = [helpers] unless _.isArray(helpers)
      for helper in helpers when typeof helper is 'string'
        try
          hlp = require(process.env.APP_HOME + "/helpers/#{helper}")
        catch e
          hlp = null
          console.log "Helper #{helper} not found".red

        if hlp
          for name, fnc of hlp when typeof fnc is 'function'
            do (name, fnc) ->
              commands[name] = (args...) ->
                try
                  fnc.apply commands, args
                catch e
                  argList = args.join(' ')
                  throw new Error "Unable to #{name}: #{argList}"

    # don't attach wd-sync's native sleep function because it fails badly when no duration is supplied
    for name, fnc of browser when typeof fnc is 'function' and name isnt 'sleep'
      do (name, fnc) ->
        # fix the URL for the "get" method
        if name is 'get'
          commands.get = (url) ->
            try
              # prepend the base url if the provided url is relative (missing http:// or https://)
              unless /^http(s)?:\/\/.*/.test(url)
                trailingSlash = /\/$/
                begginingSlash = /^\//
                # add a '/' between the base url and the relative url if needed
                if trailingSlash.test(commands.baseUrl)
                  url = url.replace(begginingSlash, '')
                else
                  url = '/' + url unless begginingSlash.test(url)
                url = commands.baseUrl + url
              fnc.call browser, url
            catch e
              throw new Error "Unable to get URL: #{url}"
        else
          commands[name] = (args...) ->
            try
              fnc.apply browser, args
            catch e
              argList = args.join(' ')
              throw new Error "Unable to #{name}: #{argList}"

    # show selenium debug messages if debug flag is set
    if ~~process.env.DEBUG
      browser.on 'status', (info) ->
        console.log info.cyan

      browser.on 'command', (meth, path, data) ->
        console.log meth.yellow, path.grey, data ? ''
   
    return null
