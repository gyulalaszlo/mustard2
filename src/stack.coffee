_ = require 'underscore'

# ## The evaluation Stack
#
# The template opcode is evaluated using this stack.
Stack =
  # Create a new stack
  make_stack: ->
    o = { current:'root', levels: {}, yields: [], yielded_from:[], used_yields:[] }
    o.levels.root = Stack.make_level 'root', null, {}
    o

  # Create a new level for the evaluation stack
  make_level: (id, parent_id, locals)->
    { id: id, locals: locals, parent_id: parent_id }

  # Create a yield stack, that references a specific
  # stack level as context.
  make_yield_level: (id, level_id, contents )->
    { id:id, contents: contents, level_id: level_id }


  # Add a new level to the stack, with parent_id as the
  # id of the stack level bellow it.
  #
  # Returns the id of the new stack level
  #
  # locals : The locals used on the current stack level.
  add_level: (stack, parent_id, locals)->
    id = _.uniqueId 'stack_'
    stack.levels[id] = Stack.make_level(id, parent_id, locals)
    id

  # Remove a level from the stack.
  remove_level: (stack, level_id)->
    delete stack.levels[level_id]


  # Get the current level of the stack.
  current_level: (stack)-> stack.levels[ stack.current ]

  get_current_locals: (stack)-> Stack.current_level(stack).locals

  # Push a new level on top of the running stack.
  push_level: (stack, locals)->
    current = Stack.current_level stack
    id = Stack.add_level stack, current.id, locals
    stack.current = id


  # Pop the topmost level of the stack
  pop_level: (stack)->
    current = Stack.current_level stack
    stack.current = current.parent_id
    id_to_remove = current.id
    Stack.remove_level stack, current.id




  push_yield_level: (stack, contents)->
    id = _.uniqueId 'yield_'
    level_id = stack.current
    stack.yields.push Stack.make_yield_level( id, level_id, contents )


  pop_yield_level: (stack)->
    stack.yields.pop()

  # Get the yield for the current context
  get_yield: (stack)->
    y = _.last stack.used_yields
    unless y
      console.log "Cannot find yield."
      console.log "STACK:-------------------------------"
      console.dir stack
    y

  # Get the contents of the yield for the current context.
  get_yield_contents: (stack)-> Stack.get_yield(stack).contents


  # Put the context of the yield on top of the existing stack (so it'll link
  # it to the original level where it was declared)
  push_yield_context: (stack)->
    current = Stack.current_level stack
    # Store the id of the current level so we can restore it later.
    stack.yielded_from.push current.id
    stack.used_yields.push stack.yields.pop()
    current_yield = Stack.get_yield stack
    # Create a new stack level and point it to the yield's context.
    id = Stack.add_level stack, current_yield.level_id, {}
    stack.current = id


  pop_yield_context: (stack)->
    old_context = stack.yielded_from.pop()
    Stack.remove_level stack, stack.current
    stack.current = old_context
    stack.yields.push stack.used_yields.pop()





  # Find a local in the stack.
  # 
  # id: the id of the top level of the stack to start the search
  # from. If null, the search starts from the current level of the stack.
  find_local: (stack, name, id=null)->
    id = stack.current if id == null
    level = stack.levels[id]
    if level == undefined
      #return null
      log_error "Cannot find level", JSON.stringify(id), 'in', JSON.stringify(stack)
      return null
    val = level.locals[name]
    return val if val != null
    return null if level.parent_id == null
    Stack.find_local stack, name, level.parent_id



    

_.extend( (module.exports ? this), Stack )
