This package adds extra IPython functionality for Emacs' python.el.
It adds the following two features:
1. Connect to and run existing jupyter consoles, e.g. on a remote server.
2. Allow IPython magic in code blocks sent to the inferior Python buffer.

The first feature is provided by the function
`ipython-shell-send/run-jupyter-existing', which is analogous
to python.el's `run-python', except it connects to an existing Jupyter
console instead of starting a new Python subprocess.

The second feature is provided by the functions
`ipython-shell-send-buffer', `ipython-shell-send-region', and
`ipython-shell-send-defun', which are analogous to `python-shell-send-*'
in python.el, except that they can handle IPython magic commands.
