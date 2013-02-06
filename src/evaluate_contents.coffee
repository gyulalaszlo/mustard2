Opcodes = require './opcodes.coffee'
Stack = require './stack.coffee'
Tokens = require './tokens.coffee'

# The main evaluator.
evaluate_contents = (o, content_tokens, blocks, definitions, stack, e_stack, contents = [])->
  for token in content_tokens
    switch token.type
      when 'STRING'
        o.push Opcodes.push( token.contents )
      when 'VARIABLE'
        # Check if the variable is available at compile time
        #local = stack.get_local token.name
        local = Stack.find_local e_stack, token.name
        # Avoid recursion if the name of the variable in the call
        # is the same name as a variable used inside the call.
        if local &&  local.length == 1 && local[0].type == 'VARIABLE' && local[0].name == token.name
          local = null
        # If the variable is avaialable at compile time, 
        # evaluate it and add it to the opcode list.
        if local
          evaluate_contents( o, local, blocks, definitions, stack, e_stack, contents)
        # If no such local is available, this should be a template
        # parameter.
        else
          o.push Opcodes.local( token.name, token.sub_keys )
      when 'SCOPE'
        scoped_local_name = token.open.name
        current_locals = Stack.get_current_locals(e_stack)
        scope_target = null
        is_compile_time = false
        # @_ is a special variable available at compile time,
        # contining all the parameters passed to the current
        # caller or all the locals when used at the top level.
        if scoped_local_name == '_'
          scope_target = current_locals
          is_compile_time = true
        else
          scope_target = Stack.find_local e_stack, scoped_local_name
          is_compile_time = Tokens.is_compile_time scope_target
          if is_compile_time
            scope_target = Tokens.compile_time_eval scope_target


        locals_count = token.locals.length
        switch locals_count
          when 0
            unless is_compile_time
              o.push Opcodes.scoped_bool( token.open.name)
              locals_used = {}
              # add a new level to the stack
              Stack.push_level e_stack, locals_used
              # Evaluate the contents of the scope.
              evaluate_contents( o, token.contents, blocks, definitions, stack, e_stack, contents)
              # Remove the locals from the scope from the stack.
              Stack.pop_level e_stack

          # If a single local is used, its either a single object
          # or an array iterating single objects.
          when 1
            l = token.locals[0]
            unless is_compile_time
              o.push Opcodes.scoped_local( token.open.name, l)
              locals_used = {}
              locals_used[l] = Opcodes.local(l)
              # add a new level to the stack
              Stack.push_level e_stack, locals_used
              # Evaluate the contents of the scope.
              evaluate_contents( o, token.contents, blocks, definitions, stack, e_stack, contents)
              # Remove the locals from the scope from the stack.
              Stack.pop_level e_stack

          # Two locals open a dictionnary by key/value pairs
          when 2
            [k,v] = token.locals
            unless is_compile_time
              locals_used = {}
              o.push Opcodes.scoped_dict( token.open.name, k, v)
              locals_used[k] = Opcodes.local(k)
              locals_used[v] = Opcodes.local(v)
              # add a new level to the stack
              Stack.push_level e_stack, locals_used
              # Evaluate the contents of the scope.
              evaluate_contents( o, token.contents, blocks, definitions, stack, e_stack, contents)
              # Remove the locals from the scope from the stack.
              Stack.pop_level e_stack

            else
              for k, v of scope_target
                as = token.locals
                locals_used = {}
                locals_used[as[0]] = [{ type: 'STRING', contents: k }]
                locals_used[as[1]] = v
                # add a new level to the stack
                Stack.push_level e_stack, locals_used
                # Evaluate the contents of the scope.
                evaluate_contents( o, token.contents, blocks, definitions, stack, e_stack, contents)
                # Remove the locals from the scope from the stack.
                Stack.pop_level e_stack


        ## Evaluate the contents of the scope.
        #evaluate_contents( o, token.contents, blocks, definitions, stack, e_stack, contents)
        ## Remove the locals from the scope from the stack.
        #Stack.pop_level e_stack
        #stack.pop()
        # Add the scope end opcode
        unless is_compile_time
          o.push Opcodes.scope_end( token.open.name )
      when 'YIELD'
        Stack.push_yield_context e_stack
        evaluate_contents(o, Stack.get_yield_contents(e_stack), blocks, definitions, stack, e_stack, [] )
        Stack.pop_yield_context e_stack
      when 'LINK'
        # Check if the linked block exists
        block_tokens = blocks[token.id]
        unless block_tokens
          error_handlers.ParseError( "Unknown linked block: #{token.id}", null) unless block_tokens
        else
          evaluate_contents(o, block_tokens, blocks, definitions, stack, e_stack, contents )
      when 'CALL'
        # Check if the linked block exists
        block_tokens = definitions[token.name]
        unless block_tokens
          error_handlers.ParseError( "Unknown symbol to call:", token.name) unless block_tokens
        else
          # Add the parameters to the stack.
          #stack.push token.name, token.parameters
          #stack.push_yield token.contents
          
          stack_frame_id = Stack.push_level e_stack, token.parameters
          Stack.push_yield_level e_stack, token.contents
          evaluate_contents(o, block_tokens, blocks, definitions, stack, e_stack, token.contents)
          Stack.pop_yield_level e_stack
          Stack.pop_level e_stack
          #stack.pop_yield
          # Pop the stack.
          #stack.pop()
  # return the constructed list
  o


module.exports = evaluate_contents
