---
status: accepted
---

# Bind view access to lexical scopes

Each `within` block defines a new lexical scope, and a Field View opened there closes once on scope exit, including normal Nim exception unwinding; an earlier end to its owning declaration's scope closes it earlier. Following Grid's `autoView`/`ViewCloser` model, copying a view copies an access handle without extending the access lifetime: the adapter separates that handle from its close responsibility, and escaped handles and Site Proxies reject use after closure. Milestone 1 exercises this protocol with shared internal lifetime scaffolding; Milestone 2 supplies native view acquisition, synchronization, and close actions, while keeping backend/device handles free of host cleanup machinery.
