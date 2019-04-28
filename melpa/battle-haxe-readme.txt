This package offers a development system for the Haxe programming language.
Haxe code completion is activated using the `company-mode' package.
Options like "go to definition" and "find all references" are available, as well as `eldoc' support.
All of those features are triggered in `battle-haxe-mode' which also spawns a Haxe server to perform them.
The tools rely on the Haxe "compiler services" feature ( https://haxe.org/manual/cr-completion-overview.html ).
The main quirk is that the system has to force automatic saving of the edited Haxe buffer.
If this is a problem for you don't use the package.
See the project home page for more information.
