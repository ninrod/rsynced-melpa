Runs a Splunk search from Emacs.  Returns the results as CSV, with option to export
to JSON and HTML.
The entry points are pepita-new-search and pepita-search-at-point
You will be prompted a query text, and time range for the query, and will get back
the results (when ready) in a new buffer.  In the results you can use:
j - to export to JSON
h - to export to HTML
? - to see the parameters used in the query
g - to refresh the results buffer
