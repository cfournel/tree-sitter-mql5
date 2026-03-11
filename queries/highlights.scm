;; Keywords
[
 "class"
 "struct"
 "enum"
 "return"
 "if"
 "else"
 "for"
 "while"
 "input"
 "extern"
 "static"
 "const"
] @keyword

;; Types
(type) @type

;; Function name
(function_definition
  name: (identifier) @function)

;; Function call
(function_call
  (identifier) @function.call)

;; Variables
(variable_declaration
  (identifier) @variable)

(parameter
  (identifier) @variable.parameter)

;; Fields
(member_expression
  (identifier) @variable)

;; Numbers
(number_literal) @number

;; Strings
(string_literal) @string

;; Comments
(comment) @comment

;; Preprocessor
(preproc_include) @preproc
(preproc_define) @preproc