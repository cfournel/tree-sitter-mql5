;; Cas 1 : fonction avec commentaire(s) juste au-dessus
(
  (comment)+ @doc
  .
  (function_definition
    name: (identifier) @function.name
  ) @function.def
)

;; Cas 2 : fonction sans commentaire
(
  (function_definition
    name: (identifier) @function.name
  ) @function.def
)