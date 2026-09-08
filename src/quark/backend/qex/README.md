# Quantum EXpressions (QEX) backend

The QEX backend will have one wrinkle: we'll need to create a view construct that is built over QEX's native notion of what's on the CPU and what's on the GPU; that is, QEX does not already provide an exact analogue of Grid's "view", but because the Grid design is so desireable, we'll want to make this notion definite and core to Quark's syntax