VC backend to work with hg repositories through hg command server.
https://www.mercurial-scm.org/wiki/CommandServer

The main advantage compared to vc-hg is speed.
Because communicating with hg over pipe is much faster than starting hg for each command.

Also there are some other improvements and differences:

- vc-hgcmd can't show file renames in `vc-dir' yet

- graph log is used for branch or root log

- Unresolved conflict status for a file
Files with unresolved merge conflicts have appropriate status in `vc-dir'.
Also you can use `vc-find-conflicted-file' to find next file with unresolved merge conflict.

- hg summary as `vc-dir' extra headers
hg summary command gives useful information about commit, update and phase states.

- Current branch is displayed on mode line.
It's not customizable yet.

- Amend and close branch commits
While editing commit message you can toggle --amend and --close-branch flags.

- Merge branch
vc-hgcmd will ask for branch name to merge.

- Default pull arguments
You can customize default hg pull command arguments.
By default it's --update. You can change it for particular pull by invoking `vc-pull' with prefix argument.

- Branches and tags as revision completion table
Instead of list of all revisions of file vc-hgcmd provides list of named branches and tags.
It's very useful on `vc-retrieve-tag'.
You can specify -C to run hg update with -C flag and discard all uncommitted changes.

- Filenames in vc-annotate buffer are hidden
They are needed to annotate changes across renames but mostly useless in annotate buffer.
vc-hgcmd removes it from annotate buffer but keep it in text properties.

- Create tag
vc-hgcmd creates tag on `vc-create-tag'
If `vc-create-tag' is invoked with prefix argument then named branch will be created.

- Predefined commit message
While committing merge changes commit message will be set to 'merged <branch>' if
different branch was merged or to 'merged <node>'.

Additionally predefined commit message passed to custom function
`vc-hgcmd-log-edit-message-function' so one can change it.
For example, to include current task in commit message:

    (defun my/hg-commit-message (original-message)
      (if org-clock-current-task
          (concat org-clock-current-task " " original-message)
        original-message))

    (custom-set-variables
     '(vc-hgcmd-log-edit-message-function 'my/hg-commit-message))
