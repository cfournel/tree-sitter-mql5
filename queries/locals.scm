;; Function scope

(function_definition) @scope


;; Parameters

(parameter
  (identifier) @definition.var)


;; Variables locales

(variable_declaration
  (identifier) @definition.var)


;; References

(identifier) @reference