Rx = require 'rx'
_ = require 'lodash'
Period = require '../functions/Period'
FunctionTypes = require '../runtime/FunctionTypes'
{CalculationError} = require '../error/Errors'
Updated = 'UPDATED'
Initial = 'INITIAL'
NotUsed = 'NOTUSED'
EvaluationComplete = 'EVALUATION_COMPLETE'

nextId = 1

class Evaluator
  constructor: (@expr, @args, subj) ->
    @id = "[#{nextId++}]"
    @subject = subj or new Rx.ReplaySubject(2, null)
    @eventsInProgress = (false for i in [0...args.length])
    @values = (Initial for i in [0...args.length])
    @isTemplate = false

  observable: -> @subject

  activate: (context) ->
    @isTemplate = context.isTemplate or false
    @_subscribeTo arg.observable(), i for arg, i in @args
    @_activateArgs context

  copy: -> throw new Error('copy must be defined')

  _activateArgs: (context) -> arg.activate(context) for arg in @args

  _evaluateIfReady: ->
    haveAllValues = not _.some @values, (x) -> x is Initial
    if haveAllValues
      nextValue = if @isTemplate then Updated else @_calculateNextValue()
      console.log 'Send:', @toString(), nextValue
      @subject.onNext nextValue
      @subject.onNext EvaluationComplete


  _calculateNextValue: -> throw new Error('_calculateNextValue must be defined')

  _subscribeTo: (obs, i) ->
    thisEval = this
    obs.subscribe (value) ->
      if value is EvaluationComplete
        eventsWereInProgress = _.some thisEval.eventsInProgress
        thisEval.eventsInProgress[i] = false
        console.log 'Comp:', thisEval.toString(), value, ' -- events', thisEval.eventsInProgress, ' -- values', thisEval.values
        eventsAreNowInProgress = _.some thisEval.eventsInProgress
        if eventsWereInProgress and not eventsAreNowInProgress then thisEval._evaluateIfReady()
      else
        thisEval.eventsInProgress[i] = true
        console.log 'Rcvd:', thisEval.toString(), value, '-- events', thisEval.eventsInProgress
        thisEval.values[i] = value

  toString: -> "#{@constructor.name} #{@expr?.text} #{@id}"

class Literal extends Evaluator
  constructor: (expr, @value) ->
    @inputStream = inputStream = new Rx.Subject()
    dummyArg =
      observable: -> inputStream
      activate: ->
        inputStream.onNext value
        inputStream.onNext EvaluationComplete

    super expr, [dummyArg]

  copy: -> new Literal @expr, @value

  _calculateNextValue: -> @value

class CalcError extends Evaluator
  constructor: (error) ->
    super null, [error]
    @latest = error

  reset: -> @values = []
  resetChildExprs: ->

class Input extends Evaluator
  constructor: (expr, @inputName) ->
    @inputStream = inputStream = new Rx.Subject()
    dummyArg =
      observable: -> inputStream
      activate: ->
        inputStream.onNext null
        inputStream.onNext EvaluationComplete

    super expr, [dummyArg]

  copy: -> new Input @expr, @inputName

  _calculateNextValue: ->
    @values[0]

  sendInput: (value) ->
    @inputStream.onNext value
    @inputStream.onNext EvaluationComplete

  toString: -> "#{@constructor.name} #{@inputName}"


class BinaryOperator extends Evaluator
  constructor: (expr, @left, @right) ->
    super expr, [@left, @right]

  _calculateNextValue: -> @op(@values[0], @values[1])

  copy: ->
    new @constructor @expr, @left.copy(), @right.copy()

  op: (a, b) -> throw new Error('op must be defined')

class Add extends BinaryOperator
  op: (a, b) ->
    switch
      when a instanceof Period and b instanceof Period
        new Period(a.millis + b.millis)
      when a instanceof Date and b instanceof Period
        new Date(a.getTime() + b.millis)
      when _.isPlainObject(a) and _.isPlainObject(b)
        _.merge {}, a, b
      when _.isArray(a) and _.isArray(b)
        a.concat b
      else
        a + b


class Subtract extends BinaryOperator
  op: (a, b) ->
    switch
      when a instanceof Date and b == null or a == null and b instanceof Date
        null
      when a instanceof Period and b instanceof Period
        new Period(a.millis - b.millis)
      when a instanceof Date and b instanceof Date
        new Period(a.getTime() - b.getTime())
      when a instanceof Date and b instanceof Period
        new Date(a.getTime() - b.millis)
      else
        a - b


class Multiply extends BinaryOperator
  op: (a, b) -> a * b

class Divide extends BinaryOperator
  op: (a, b) -> a / b

class Eq extends BinaryOperator
  op: (a, b) -> a == b

class NotEq extends BinaryOperator
  op: (a, b) -> a != b

class Gt extends BinaryOperator
  op: (a, b) -> a > b

class GtEq extends BinaryOperator
  op: (a, b) -> a >= b

class Lt extends BinaryOperator
  op: (a, b) -> a < b

class LtEq extends BinaryOperator
  op: (a, b) -> a <= b

class And extends BinaryOperator
  op: (a, b) -> a && b

class Or extends BinaryOperator
  op: (a, b) -> a || b

#TODO new values if function changes
class FunctionCallNoArgs extends Evaluator
  constructor: (expr, @name) ->
    super expr, [null]

  activate: (context) ->
    if context.userFunctions[@name]
      obs = context.userFunctions[@name]
      log = (x) => console.log 'Pass:', @toString(), x
      obs.do(log).subscribe @subject
    else
      source = context.providedFunctions[@name]
      value = source()
      obs = new Rx.Observable.from([value, EvaluationComplete])
      @_subscribeTo obs, 0

  copy: -> new FunctionCallNoArgs @expr, @name

  _calculateNextValue: -> @values[0]

#TODO new values if function changes
class FunctionCallWithArgs extends Evaluator
  constructor: (expr, @name, args) ->
    super expr, args

  activate: (context) ->
    if @func = context.userFunctions[@name]
      @isUserFunction = true
      @context = context
      @func.subscribe @_updateFunction
    else
      @func = context.providedFunctions[@name]
      @isUserFunction = false
      if @func.returnKind == FunctionTypes.STREAM_RETURN
        @_subscribeStreamFunction @func
      else
        @_subscribeTo arg.observable(), i for arg, i in @args

    @_activateArgs context

  copy: -> new FunctionCallWithArgs @expr, @name, (a.copy() for a in @args)

  _updateFunction: (funcDef) =>
    argSubject = (arg) ->
      subj = new Rx.Subject()
      arg.observable().subscribe subj
      subj
    subjects = (argSubject arg for arg in @args)
    argSubjects = _.zipObject funcDef.argNames, subjects
    @evaluator = funcDef.evaluatorTemplate.copy()
    contextWithArgs = _.merge {}, @context, {argSubjects}
    @evaluator.activate(contextWithArgs)
    @_subscribeTo @evaluator.observable(), 0
    #TODO hack
    @values = (null for i in [1...@args.length])

  _subscribeStreamFunction: (fn) ->
    #TODO requires function to handle EvaluationComplete
    rawArgObs = (arg.observable() for arg in @args)
    outputObs = fn.apply null, rawArgObs
    outputObs.subscribe @subject

  _calculateNextValue: ->
    console.log @toString(), '_calculateNextValue', @values
    if @isUserFunction
      @values[0]
    else
      @func.apply null, @values

#TODO does this belong in here?
class FunctionDefinition
  constructor: (@argNames, @evaluatorTemplate) ->

class ArgRef extends Evaluator
  constructor: (@name) ->
    super {text: name}, [null]

  activate: (context) ->
    obs = context.argSubjects[@name] or context.argSubjects.__anyArg
    @_subscribeTo obs, 0

  copy: -> new ArgRef @name

  _calculateNextValue: -> @values[0]

class Aggregation extends Evaluator
  constructor: (expr, @names, @items) ->
    super expr, items

  copy: -> new Aggregation @expr, @names, (a.copy() for a in @items)

  _calculateNextValue: -> _.zipObject @names, @values

class Sequence extends Evaluator
  constructor: (expr, @items) ->
    super expr, items

  copy: -> new Sequence @expr, (a.copy() for a in @items)

  _calculateNextValue: -> @values


class AggregationSelector extends Evaluator
  constructor: (expr, @aggregation, @elementName) ->
    super expr, [aggregation]

  copy: -> new AggregationSelector @expr, @aggregation.copy(), @elementName

  _calculateNextValue: -> @values[0][@elementName]

class ExpressionFunction extends Evaluator
  constructor: (@evaluator) ->
    super evaluator.expr, []

  activate: (context) ->
    @context = context
    exprContext = _.merge {}, context, {argSubjects: {__anyArg: Rx.Observable.from([NotUsed, EvaluationComplete])}, isTemplate: true }
    @evaluator.activate exprContext
    @_subscribeTo @evaluator.observable(), 0

  copy: -> new ExpressionFunction @evaluator.copy()

  _calculateNextValue: ->
    result = undefined
    evaluator = @evaluator.copy()
    evaluator.observable().subscribe (x) ->
      if x isnt EvaluationComplete then result = x
    argInput = new Rx.Subject()
    context = _.merge {}, @context, {argSubjects: {in: argInput}}
    evaluator.activate context
    (_in) ->
      argInput.onNext _in
      argInput.onNext EvaluationComplete
      result


module.exports = {Literal, Error, Add, Subtract,Multiply, Divide, Eq, NotEq, Gt, Lt, GtEq, LtEq, And, Or,
  FunctionCallNoArgs, FunctionCallWithArgs, Input, Aggregation, Sequence, AggregationSelector, ArgRef, EvaluationComplete, FunctionDefinition, ExpressionFunction}