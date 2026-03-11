;; Functions

(function_definition
  name: (identifier) @name) @definition.function


;; Classes

(class_definition
  name: (identifier) @name) @definition.class


;; Structs

(struct_definition
  (identifier) @name) @definition.struct


;; Enums

(enum_definition
  (identifier) @name) @definition.enum


;; Variables globales

(variable_declaration
  (identifier) @name) @definition.variable


;; Function calls

(function_call
  (identifier) @name) @reference.call