Pulling external file changes to a tangled org-babel src block
is surprisingly not an implemented feature.  This addresses that.

Any block that has :tangle <fname> will compare the block with
that external <fname>.  When a diff is detected, 1 of 4 actions
can occur:
  1. External - <fname> contents will override the block contents
  2. Internal - block will keep the block contents
  3. Prompt - The user will be prompted to pull external changes
  4. Diff - A diff of the <fname> and block contents will be produced
  5. Custom - A user-defined function will be called instead.

These 5 options can be set as the default action by changing the
`org-tanglesync-default-diff-action` custom parameter.  Otherwise
individual block actions can be set in the org src block header
e.g. `:diff external` for pulling external changes without
prompt into a specific block.

This package also provides a hook when the org src block is
being edited (e.g. via `C-c '`) which asks the user if they
want to pull external changes if a difference is detected.
The user can bypass this and always pull by setting the
`org-tanglesync-skip-user-check` custom parameter.
