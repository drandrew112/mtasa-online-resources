# UI modules

The active job browser and lobby UI are in `core/client/ui.lua`. This directory
is reserved for optional visual subcomponents. Server interaction must use the
validated `jobmanager:*` events rather than client-side state.
