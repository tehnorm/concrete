express = require 'express'
stylus = require 'stylus'
gravatar = require 'gravatar'
fs = require 'fs'
path = require 'path'
runner = require './runner'
jobs = require './jobs'
git = require './git'
require 'express-namespace'

authorize = (user, pass) ->
    user == git.user and pass == git.pass

if git.user and git.pass
    app = module.exports = express.createServer(express.basicAuth(authorize))
else
    app = module.exports = express.createServer()

app.helpers
  baseUrl: ->
    path.normalize("#{global.currentNamespace}/")

  gravatar: (email)->
    gravatar.url(email, {s: '30', r: 'pg'})


app.configure ->
    app.set 'views', __dirname + '/views'
    app.set 'quiet', yes
    # use coffeekup for html markup
    app.set 'view engine', 'coffee'
    app.register '.coffee', require('coffeekup').adapters.express
    app.set 'view options', {
        layout: false
    }

    # this must be BEFORE other app.use
    app.use stylus.middleware
        debug: false
        src: __dirname + '/views'
        dest: __dirname + '/public'
        compile: (str)->
            stylus(str).set 'compress', true

    coffeeDir = __dirname + '/views'
    publicDir = __dirname + @_locals.baseUrl() + '/public'
    app.use express.compiler src: coffeeDir, dest: publicDir, enable: ['coffeescript']

    app.use express.logger()
    app.use express.bodyParser()
    app.use app.router
    app.use global.currentNamespace, express.static __dirname + '/public'

app.configure 'development', ->
    app.use express.errorHandler dumpExceptions: on, showStack: on

app.configure 'production', ->
    app.use express.errorHandler dumpExceptions: on, showStack: on

deferredApp = ->
  app.get '/', (req, res) ->
      jobs.getAll (jobs)->
          res.render 'index',
              project: path.basename process.cwd()
              jobs: jobs

  app.get '/jobs', (req, res) ->
      jobs.getAll (jobs)->
          res.json jobs

  app.get '/job/:id', (req, res) ->
      jobs.get req.params.id, (job) ->
          res.json job

  app.get '/job/:id/:attribute', (req, res) ->
      jobs.get req.params.id, (job) ->
          if job[req.params.attribute]?
              # if req.xhr...
              res.json job[req.params.attribute]
          else
              res.send "The job doesn't have the #{req.params.attribute} attribute"

  app.get '/clear', (req, res) ->
      jobs.clear ->
          res.redirect "#{@_locals.baseUrl()}/jobs"

  app.get '/add', (req, res) ->
      jobs.addJob ->
          res.redirect "#{@_locals.baseUrl()}/jobs"

  app.get '/ping', (req, res) ->
      jobs.getLast (job) ->
          if job.failed
              res.send(412)
          else
              res.send(200)

  app.post '/', (req, res) ->
      if req.body.payload?
        try
          payload = JSON.parse req.body.payload
        catch error
          console.log error
          payload = null
      else
        payload = null

      jobs.addJob (job)->
          runner.build()
          if req.xhr
              res.json job
          else
              res.redirect "#{@_locals.baseUrl()}/"
      , payload

if global.currentNamespace != "/"
  app.namespace global.currentNamespace, deferredApp
else
  deferredApp()
