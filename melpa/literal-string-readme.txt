Literal String Mode is a minor mode for editing multi-line literal
strings in a dedicated buffer.

When enabled, edit the literal string at point using C-c '
(literal-string-edit-string), this will copy the (unescaped and
deindented) content of the string to a dedicated literal string
editing buffer that has Literal String Editing Mode (a minor mode)
enabled.

To exit the current literal string buffer copy the edited string
back into the original source buffer with correct quoting and
escape sequences, press C-c '
(literal-string-edit-string-exit).

To discard your changes to the editing buffer, press C-c C-k
(literal-string-edit-string-abort)

To enable literal-string-mode in your preferred programming modes,
turn it on using the relevant mode hooks.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2, or (at your option)
any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor,
Boston, MA 02110-1301, USA.
