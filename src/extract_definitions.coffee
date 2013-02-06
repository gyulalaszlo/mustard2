
# Extract a list of definitions from the tokens
extract_definitions = ( tokens )->
  definitions = {}
  # all definitions are on the top level of the token stream
  for token in tokens
    continue if token.type != 'DEFINE'
    definitions[token.name] = token.contents

  definitions


module.exports = extract_definitions
