Purpose:

 Fast search for selected org nodes and things outside of org.

 org-index creates and updates an index table with keywords; each line
 either points to a heading in org, references something outside or
 carries a snippet of text to yank.  When searching the index, the set
 of matching lines is updated with every keystroke; results are sorted
 by usage count and date, so that frequently used entries appear first
 in the list of results.

 In addition, org-index introduces these supplemental concepts:

 - References are decorated numbers (e.g. 'R237' or '--455--'); they are
   well suited to be used outside of org, e.g. in folder names,
   ticket systems or on printed documents.
 - Focus is a small set of nodes for your daily work; it can be managed
   and traversed easily.

 On first invocation org-index will assist you in creating the index
 table.

 To start using your index, invoke the subcommand 'add' to create
 entries and 'occur' to find them.


Setup:

 - org-index can be installed with package.el
 - Invoke `org-index'; on first run it will assist in creating your
   index table.

 - Optionally invoke `M-x org-customize', group 'Org Index', to tune
   its settings.


Further information:

 - Watch the screencast at http://2484.de/org-index.html.
 - See the documentation of `org-index', which can also be read by
   invoking `org-index' and typing '?'.
