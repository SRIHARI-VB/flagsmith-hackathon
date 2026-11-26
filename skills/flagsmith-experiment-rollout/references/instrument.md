# Instrumenting an experiment (minimum SDK versions with events support)

Rules for every language: enable events, use one identifier for flags and events, evaluate with the experiment call where the user sees the variant, track the metric event with the exact name, flush before exit.

## React (`@flagsmith/flagsmith` ≥ 12.4.0)
```jsx
<FlagsmithProvider flagsmith={flagsmith} options={{ environmentID, identity: userId, enableEvents: true }}>
// in a component:
const flag = useExperiment('my_flag');           // records the exposure; null until loaded
const flagsmith = useFlagsmith();
flagsmith.trackEvent('signup_completed');        // conversion
// flush on leave:
addEventListener('pagehide', () => flagsmith.flushEvents());
```
Render only after flags come from the server (`useFlagsmithLoading().source === 'SERVER'`), or the default value flashes before the assigned variant.

## JavaScript (browser)
```js
await flagsmith.init({ environmentID, enableEvents: true });
await flagsmith.identify(userId);
const flag = flagsmith.getExperimentFlag('my_flag'); // flag.value = variant value
flagsmith.trackEvent('signup_completed');
await flagsmith.flushEvents();
```

## Node.js (`@flagsmith/nodejs` ≥ 9.1.0)
```js
const flagsmith = new Flagsmith({ environmentKey, enableEvents: true });
const flag = await flagsmith.getExperimentFlag('my_flag', userId);
flagsmith.trackEvent('signup_completed', { identifier: userId });
await flagsmith.close(); // flushes
```

## Python (`flagsmith` ≥ 6.3.0)
```python
flagsmith = Flagsmith(environment_key=KEY, enable_events=True)
flag = flagsmith.get_experiment_flag("my_flag", identifier=user_id)
flagsmith.track_event("signup_completed", identifier=user_id)
# short scripts: EventProcessorConfig(max_buffer_items=1) so events send immediately
```

## Go (`flagsmith-go-client/v5` ≥ v5.3.0)
```go
client := flagsmith.NewClient(key, flagsmith.WithEvents(eventsCtx))
flag, _ := client.GetExperimentFlag(ctx, "my_flag", ec)
client.TrackEvent("signup_completed", &flagsmith.EventOptions{Identifier: userID})
client.FlushEvents(ctx)
```

Others: Java `getExperimentFlag(name, identity)` / `trackEvent(...)` / `close()` (≥ 8.2.0); Flutter `getExperimentFlag(name, user:)` / `trackEvent(...)` / `flushEvents()` (≥ 6.2.0).

Self-hosted: point the SDK API at `<host>/api/v1/` and the events URL at the instance's events endpoint.
