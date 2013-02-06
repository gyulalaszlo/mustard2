_ = require 'underscore'

# Extract all the blocks (list of tokens) deeper then the main token list
# into a separate list, get a copy of the top-level tokens with these references.
# This should enable to handle mustard templates in a more linear fashion.
#
# Returns
# [ list, linked_tokens]:
#
# ### list:   
#
# The collected list of blocks keyed by filename/id. 
# This is updated
#
# ### linked_tokens
#
# A list of the current level tokens replaced with their linked id.
replace_tokens_with_links = (filename, tokens, list={})->
  linked_tokens = []
  for token in tokens
    if token.type == 'CALL' || token.type == 'DEFINE'
      contents = token.contents
      continue unless contents
      # Go recursive without adding the child tokens 
      # to the linked_tokens.
      replace_tokens_with_links filename, contents, list
      # the id is the current length of the list
      id = "#{filename}:#{ _.size list }"
      list[id] = contents
      token.contents = [{ type: 'LINK', id: id }]

    # Add the -possibly modified token-
    # to the linked list
    linked_tokens.push token

  [list, linked_tokens]
  

module.exports = replace_tokens_with_links
