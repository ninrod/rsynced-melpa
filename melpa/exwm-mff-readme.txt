Mouse Follows Focus
===================

Traditional window managers are mouse-centric: the window to receive
input is usually selected with the pointing device.

Emacs is keybord-centric: the window to receive key input is usually
selected with the keyboard.  When you use the keyboard to focus a
window, the spatial relationship between pointer and active window is
broken -- the pointer can be anywhere on the screen, instead of over
the active window, which can make it hard to find.

(The same problem exists in traditional windowing systems when you use
the keyboard to switch windows, e.g. with Alt-Tab.  But we can’t do
anything about that here.)

Because Emacs’ model is inversed, this suggests that the correct
behavior is also the inverse -- instead of using the mouse to select a
window to receive keyboard input, the keyboard should be used to
select the window to receive mouse input.

`EXWM-MFF-MODE' is a global minor mode which does exactly this.  When
the selected window in Emacs changes, the mouse pointer is moved to
its center, unless the pointer is already somewhere inside the
window’s bounds.  It works for both regular Emacs windows and X11
clients managed by EXWM.

This package also offers the `EXWM-MFF-WARP-TO-SELECTED' command,
which allows you to summon the pointer with a hotkey.  Unlike the
minor mode, summoning is unconditional, and will place the pointer in
the center of the window even if it already resides within its bounds
-- a handy feature if you’ve lost your pointer, even if you’re using
the minor mode.


Limitations
~~~~~~~~~~~

Handling of floating frames needs some work; clicking the modeline of
a buffer warps the point to the center of the buffer, rather than
leaving it where it was when clicked.
