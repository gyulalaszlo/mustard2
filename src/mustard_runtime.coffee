# # The mustard runtime
_ = require 'underscore'


Runtime =
  new_scope : (locals)-> [locals]

  # Start a scope.
  start_scope : (scope, object)-> scope.push object
  end_scope : (scope, object)-> scope.pop

  get_from_scope : (scope, name)->
    idx = scope.length - 1
    while idx >= 0
      o = scope[idx]
      v = o[name]
      return v if v
      idx -= 1
    return null



  get_single : (scope, name)->
    o = Runtime.get_from_scope(scope,name)
    if _.isArray(o)
      o
    else
      [o]

  get_dict : (scope, name)->
    o = Runtime.get_from_scope(scope,name)
    if _.isObject(o)
      _.pairs o
    else
      []


  get_bool : (scope, name)->
    o = Runtime.get_from_scope(scope,name)
    # return false for null, undefined and false
    return false unless o
    # return false for empty strings
    return false if _.isString(o) && o.length == 0
    # return false for empty arrays
    return false if _.isArray(o) && o.length == 0
    true


_.extend( (module.exports ? this), Runtime )
