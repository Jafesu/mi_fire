# Events

## Client events

| Event | Payload | Meaning |
|---|---|---|
| `mi_fire:client:teardown` | none | The resource is stopping. Clean up anything you attached to it. |

## Notes

Net events that accept player input are validated at the service boundary. Job, position,
and distance are all re-checked server side against where the server believes that player
is, so triggering one directly from a client does not bypass anything.

More events are added as phases ship. See
[internal/CONTRACTS.md](../internal/CONTRACTS.md) for the authoritative list.
