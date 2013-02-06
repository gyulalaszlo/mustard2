
# Extract the top level template content from the tokens
extract_contents = (tokens)->
  contents = []
  # all definitions are on the top level of the token stream
  for token in tokens
    continue if token.type == 'DEFINE'
    contents.push token

  contents


module.exports = extract_contents
