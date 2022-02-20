A very simple marshalling library between XML and Nim structures. This library
is primarily intended to fill the absence of such a library. For anyone
familiar in marshalling, this implementation should work predictably.

XML marshalling is not straightforward, and commonly requires specialization.
As such some custom pragmas are available that can be annotated on object
fields to specialize the marshalling. See `xmlserde/common.nim` for these
pragmas.

For further documentation, please compile the Nim documentation for this
project.

# License

MIT
