; Copyright 2025 nvim-treesitter
;
; Licensed under the Apache License, Version 2.0 (the "License");
; you may not use this file except in compliance with the License.
; You may obtain a copy of the License at
;
;     http://www.apache.org/licenses/LICENSE-2.0
;
; Unless required by applicable law or agreed to in writing, software
; distributed under the License is distributed on an "AS IS" BASIS,
; WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
; See the License for the specific language governing permissions and
; limitations under the License.

; inherits: ecma

; styled.div<{}>`<css>`
(call_expression
  function: (non_null_expression
    (instantiation_expression
      (member_expression
        object: (identifier) @_name
        (#eq? @_name "styled")
        property: (property_identifier))
      type_arguments: (type_arguments)))
  arguments: ((template_string) @injection.content
    (#offset! @injection.content 0 1 0 -1)
    (#set! injection.include-children)
    (#set! injection.language "styled")))

; styled.div<T>`<css>`
(binary_expression
  left: (binary_expression
    left: (member_expression
      object: (identifier) @_name
      (#eq? @_name "styled")
      property: (property_identifier))
    right: (identifier))
  right: (template_string) @injection.content
  (#offset! @injection.content 0 1 0 -1)
  (#set! injection.include-children)
  (#set! injection.language "styled"))
